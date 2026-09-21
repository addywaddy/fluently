defmodule Fluently.Accounts do
  @moduledoc "Registered accounts. Guest review sessions never create or upgrade accounts."
  import Ecto.Query
  import Ecto.Changeset
  alias Fluently.{Repo, Feedback}
  alias Fluently.Accounts.{Account, AccountMembership, AccountSession}
  alias Fluently.Feedback.{Workspace, Thread}

  def current(token) when is_binary(token) do
    now = DateTime.utc_now()

    account =
      Repo.one(
        from s in AccountSession,
          join: a in Account,
          on: a.id == s.account_id,
          where: s.token_hash == ^Feedback.hash(token) and s.expires_at > ^now,
          where: a.session_expires_at > ^now,
          where: is_nil(a.expires_at) or a.expires_at > ^now,
          select: a
      ) ||
        Repo.one(
          from a in Account,
            where: a.session_hash == ^Feedback.hash(token) and a.session_expires_at > ^now,
            where: is_nil(a.expires_at) or a.expires_at > ^now
        )

    account
    |> ensure_user()
  end

  def current(_), do: nil

  # Old containers can finish a signup between the migration and release switch.
  def ensure_user(%Account{email: email, user_id: nil} = account) when not is_nil(email) do
    {:ok, account} =
      Repo.transaction(fn ->
        Repo.insert!(%Fluently.Accounts.User{id: account.id, kind: "registered"},
          on_conflict: :nothing
        )

        account = account |> change(user_id: account.id) |> Repo.update!()
        ensure_owner_membership(account)
        account
      end)

    account
  end

  def ensure_user(account), do: account

  def demo_enabled?, do: Application.get_env(:fluently, :demo_enabled, true)
  def private_feedback_only?, do: Application.get_env(:fluently, :private_feedback_only, false)

  def public_project do
    case Feedback.project(Application.get_env(:fluently, :feedback_project_id)) do
      %{public_feedback: true} = project -> project
      _ -> nil
    end
  end

  def register(account, attrs) do
    # Hash outside the transaction; the writer only stays reserved for database work.
    changeset = registration_changeset(%Account{}, attrs)

    if changeset.valid? do
      salt = :crypto.strong_rand_bytes(16)
      password_hash = password_hash(get_change(changeset, :password), salt)

      Repo.transaction(fn ->
        if account && account.email, do: Repo.rollback(:already_registered)

        {:ok, workspace, _} =
          Feedback.create_workspace(get_change(changeset, :name) <> "’s workspace")

        user = Repo.insert!(%Fluently.Accounts.User{kind: "registered"})
        account = %Account{workspace_id: workspace.id, user_id: user.id}
        token = Feedback.secret()

        account =
          account
          |> registration_changeset(attrs)
          |> put_change(:password_hash, password_hash)
          |> put_change(:password_salt, salt)
          |> put_change(:expires_at, nil)
          |> put_change(:session_hash, Feedback.hash(token))
          |> put_change(:session_expires_at, DateTime.add(DateTime.utc_now(), 30, :day))
          |> Repo.insert()
          |> unwrap!()

        ensure_owner_membership(account)
        create_session(account, token)

        Repo.get!(Workspace, account.workspace_id)
        |> change(name: account.name <> "’s workspace")
        |> Repo.update!()

        {account, token}
      end)
    else
      {:error, changeset}
    end
  end

  def login(email, password)
      when is_binary(email) and is_binary(password) and byte_size(password) <= 1024 do
    account = Repo.get_by(Account, email: String.downcase(String.trim(email)))
    salt = if account, do: account.password_salt, else: <<0::128>>
    expected = if account, do: account.password_hash, else: <<0::256>>
    actual = password_hash(password, salt)

    if Plug.Crypto.secure_compare(actual, expected) and account do
      account = ensure_user(account)
      token = Feedback.secret()

      {:ok, account} =
        account
        |> change(
          session_hash: Feedback.hash(token),
          session_expires_at: DateTime.add(DateTime.utc_now(), 30, :day)
        )
        |> Repo.update()

      create_session(account, token)

      {:ok, account, token}
    else
      {:error, :unauthorized}
    end
  end

  def login(_, _), do: {:error, :unauthorized}

  def logout(nil), do: :ok

  def logout(account),
    do:
      Repo.transaction(fn ->
        Repo.delete_all(from s in AccountSession, where: s.account_id == ^account.id)
        account |> change(session_hash: nil, session_expires_at: nil) |> Repo.update!()
      end)

  # Remove legacy private demos only; shared project feedback is independent.
  def prune_expired do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      accounts =
        Repo.all(
          from a in Account,
            where: not is_nil(a.expires_at) and a.expires_at <= ^now,
            limit: 500
        )

      for account <- accounts do
        projects = Feedback.projects(%Workspace{id: account.workspace_id}) |> Enum.map(& &1.id)
        Repo.delete_all(from t in Thread, where: t.project_id in ^projects)
        Repo.delete!(account)
        Repo.delete!(Repo.get!(Workspace, account.workspace_id))
      end

      length(accounts)
    end)
  end

  defp registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :email, :password])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:name, :email, :password])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:email, max: 160)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> validate_length(:password, min: 15, max: 128)
    |> validate_change(:password, fn :password, value ->
      if byte_size(value) > 1024, do: [password: "is too long"], else: []
    end)
    |> unique_constraint(:email)
  end

  defp password_hash(password, salt),
    do: :crypto.pbkdf2_hmac(:sha256, password, salt, 600_000, 32)

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)

  defp ensure_owner_membership(%Account{id: account_id, user_id: user_id})
       when is_binary(user_id) do
    Repo.insert!(
      %AccountMembership{account_id: account_id, user_id: user_id, role: "owner"},
      on_conflict: :nothing,
      conflict_target: [:account_id, :user_id]
    )
  end

  defp ensure_owner_membership(_), do: :ok

  defp create_session(%Account{user_id: user_id, id: account_id}, token)
       when is_binary(user_id) and is_binary(token) do
    Repo.insert!(%AccountSession{
      account_id: account_id,
      user_id: user_id,
      token_hash: Feedback.hash(token),
      expires_at: DateTime.add(DateTime.utc_now(), 30, :day)
    })
  end
end
