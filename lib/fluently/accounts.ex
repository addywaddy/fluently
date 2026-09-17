defmodule Fluently.Accounts do
  @moduledoc "Guest feedback identities, upgraded in place at registration; legacy demos stay private."
  import Ecto.Query
  import Ecto.Changeset
  alias Fluently.{Repo, Feedback, Threads}
  alias Fluently.Accounts.Account
  alias Fluently.Feedback.{Reviewer, Workspace, Thread}

  def current(token) when is_binary(token) do
    now = DateTime.utc_now()

    Repo.one(
      from a in Account,
        where: a.session_hash == ^Feedback.hash(token) and a.session_expires_at > ^now,
        where: is_nil(a.expires_at) or a.expires_at > ^now
    )
  end

  def current(_), do: nil

  def demo_enabled?, do: Application.get_env(:fluently, :demo_enabled, true)

  def public_project do
    case Feedback.project(Application.get_env(:fluently, :feedback_project_id)) do
      %{public_feedback: true} = project -> project
      _ -> nil
    end
  end

  def demo_project(account) do
    if Application.get_env(:fluently, :feedback_project_id),
      do: public_project(),
      else: if(account, do: Feedback.project(account.demo_project_id), else: nil)
  end

  def first_comment(account, attrs, origin) do
    Repo.transaction(fn ->
      if not demo_enabled?(), do: Repo.rollback(:disabled)
      {account, token} = if account, do: {reload_active_account(account), nil}, else: anonymous!()
      {account, project, reviewer} = ensure_demo!(account, origin)

      case Threads.create(project, reviewer, attrs) do
        {:ok, thread} -> %{account: account, token: token, thread: thread}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def reviewer(nil), do: nil

  def reviewer(account) do
    id =
      if Application.get_env(:fluently, :feedback_project_id),
        do: account.feedback_reviewer_id,
        else: account.reviewer_id

    if id, do: Repo.get(Reviewer, id)
  end

  def register(account, attrs) do
    # Hash outside the transaction; the writer only stays reserved for database work.
    changeset = registration_changeset(%Account{}, attrs)

    if changeset.valid? do
      salt = :crypto.strong_rand_bytes(16)
      password_hash = password_hash(get_change(changeset, :password), salt)

      Repo.transaction(fn ->
        account = if account, do: reload_active_account(account), else: elem(anonymous!(), 0)
        if account.email, do: Repo.rollback(:already_registered)
        token = Feedback.secret()

        account =
          account
          |> registration_changeset(attrs)
          |> put_change(:password_hash, password_hash)
          |> put_change(:password_salt, salt)
          |> put_change(:expires_at, nil)
          |> put_change(:session_hash, Feedback.hash(token))
          |> put_change(:session_expires_at, DateTime.add(DateTime.utc_now(), 30, :day))
          |> Repo.update()
          |> unwrap!()

        Repo.get!(Workspace, account.workspace_id)
        |> change(name: account.name <> "’s workspace")
        |> Repo.update!()

        for id <- [account.reviewer_id, account.feedback_reviewer_id], not is_nil(id) do
          Repo.get!(Reviewer, id) |> change(name: account.name, kind: "account") |> Repo.update!()
        end

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
      token = Feedback.secret()

      {:ok, account} =
        account
        |> change(
          session_hash: Feedback.hash(token),
          session_expires_at: DateTime.add(DateTime.utc_now(), 30, :day)
        )
        |> Repo.update()

      {:ok, account, token}
    else
      {:error, :unauthorized}
    end
  end

  def login(_, _), do: {:error, :unauthorized}

  def logout(nil), do: :ok

  def logout(account),
    do: account |> change(session_hash: nil, session_expires_at: nil) |> Repo.update()

  # The immediate transaction serializes expiry with signup before reading identities.
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

  defp anonymous! do
    {:ok, workspace, _} = Feedback.create_workspace("Your private demo")
    token = Feedback.secret()

    account =
      %Account{
        workspace_id: workspace.id,
        session_hash: Feedback.hash(token),
        session_expires_at: DateTime.add(DateTime.utc_now(), 30, :day),
        expires_at: DateTime.add(DateTime.utc_now(), 14, :day)
      }
      |> Repo.insert!()

    {account, token}
  end

  defp ensure_demo!(account, origin) do
    if Application.get_env(:fluently, :feedback_project_id) do
      project = public_project() || Repo.rollback(:unavailable)
      reviewer = reviewer(account)

      if reviewer && reviewer.project_id == project.id do
        {account, project, reviewer}
      else
        reviewer =
          Repo.insert!(%Reviewer{
            project_id: project.id,
            name: account.name || "Visitor",
            kind: if(account.email, do: "account", else: "anonymous")
          })

        account = account |> change(feedback_reviewer_id: reviewer.id) |> Repo.update!()
        {account, project, reviewer}
      end
    else
      ensure_private_demo!(account, origin)
    end
  end

  defp ensure_private_demo!(account, origin) do
    case demo_project(account) do
      nil ->
        project =
          case Feedback.create_project(
                 %Workspace{id: account.workspace_id},
                 %{"name" => "My Fluently demo", "origin" => origin}
               ) do
            {:ok, project, _} -> project
            {:error, error} -> Repo.rollback(error)
          end

        reviewer =
          %Reviewer{
            project_id: project.id,
            name: account.name || "You",
            kind: if(account.email, do: "account", else: "anonymous")
          }
          |> Repo.insert!()

        account =
          account
          |> change(demo_project_id: project.id, reviewer_id: reviewer.id)
          |> Repo.update!()

        {account, project, reviewer}

      project ->
        {account, project, reviewer(account)}
    end
  end

  defp reload_active_account(account) do
    now = DateTime.utc_now()

    Repo.one(
      from a in Account,
        where: a.id == ^account.id and a.session_hash == ^account.session_hash,
        where: a.session_expires_at > ^now and (is_nil(a.expires_at) or a.expires_at > ^now)
    ) || Repo.rollback(:expired)
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
end
