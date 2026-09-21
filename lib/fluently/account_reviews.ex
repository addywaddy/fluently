defmodule Fluently.AccountReviews do
  @moduledoc "Explicit project-member review sessions; independent of third-party cookies."
  import Ecto.Query
  alias Fluently.{Repo, Feedback, ProjectAccess, Accounts}
  alias Fluently.Accounts.{Account, AccountSession}
  alias Fluently.Projects.{ProjectAdmin, ProjectUser}
  alias Fluently.Reviews.{Actor, ReviewGrant}

  def valid_nonce?(value), do: is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9_-]{43}\z/, value)

  def return_url?(project, value) when is_binary(value) and byte_size(value) <= 1024 do
    with {:ok, uri} <- URI.new(value),
         true <- is_nil(uri.userinfo) and not String.contains?(value, ["\\", "\r", "\n"]) do
      URI.to_string(%{uri | path: nil, query: nil, fragment: nil}) == project.origin
    else
      _ -> false
    end
  end

  def return_url?(_, _), do: false

  def member?(%Account{email: email} = account, project) when not is_nil(email),
    do: ProjectAccess.authorized?(account, project)

  def member?(_, _), do: false

  def issue(project, account, challenge) do
    Repo.transaction(fn ->
      expected_session = account && account.session_hash
      account = account && Repo.get(Account, account.id)

      session =
        account && account.session_hash &&
          Repo.get_by(AccountSession, account_id: account.id, token_hash: account.session_hash)

      unless member?(account, project) and valid_nonce?(challenge) and live_account?(account) and
               account.session_hash == expected_session and not is_nil(session) and
               DateTime.compare(session.expires_at, DateTime.utc_now()) == :gt,
             do: Repo.rollback(:unauthorized)

      membership =
        if Accounts.private_feedback_only?() do
          Repo.get_by(ProjectAdmin, project_id: project.id, workspace_id: account.workspace_id) ||
            Repo.insert!(%ProjectAdmin{
              project_id: project.id,
              workspace_id: account.workspace_id
            })
        else
          {:ok, _} = ProjectAccess.reviewer(%{id: account.workspace_id}, project)
          Repo.get_by!(ProjectAdmin, project_id: project.id, workspace_id: account.workspace_id)
        end

      code = Feedback.secret()

      Repo.insert!(%ReviewGrant{
        project_id: project.id,
        account_id: account.id,
        account_session_id: session.id,
        membership_id: membership && membership.id,
        account_session_hash: account.session_hash,
        credential_version: project.credential_version,
        challenge: challenge,
        code_hash: Feedback.hash(code),
        expires_at: DateTime.add(DateTime.utc_now(), 90, :second)
      })

      code
    end)
  end

  def exchange(project, code, verifier) when is_binary(code) and is_binary(verifier) do
    Repo.transaction(fn ->
      unless valid_nonce?(code) and valid_nonce?(verifier), do: Repo.rollback(:unauthorized)
      grant = Repo.get_by(ReviewGrant, project_id: project.id, code_hash: Feedback.hash(code))

      with %ReviewGrant{} <- grant,
           true <- grant.challenge == Base.url_encode64(Feedback.hash(verifier), padding: false),
           {:ok, identity} <- identity(project, grant) do
        token = Feedback.secret()

        grant
        |> Ecto.Changeset.change(
          code_hash: nil,
          token_hash: Feedback.hash(token),
          expires_at: DateTime.add(DateTime.utc_now(), 24, :hour)
        )
        |> Repo.update!()

        %{token: token, identity: identity}
      else
        _ -> Repo.rollback(:unauthorized)
      end
    end)
  end

  def exchange(_, _, _), do: {:error, :unauthorized}

  def authorize(project, token) when is_binary(token) do
    if valid_nonce?(token) do
      case Repo.get_by(ReviewGrant, project_id: project.id, token_hash: Feedback.hash(token)) do
        nil -> {:error, :unauthorized}
        grant -> identity(project, grant)
      end
    else
      {:error, :unauthorized}
    end
  end

  def authorize(_, _), do: {:error, :unauthorized}

  def revoke(project, token) do
    if is_binary(token),
      do:
        Repo.delete_all(
          from g in ReviewGrant,
            where: g.project_id == ^project.id and g.token_hash == ^Feedback.hash(token)
        )

    :ok
  end

  def prune_expired do
    now = DateTime.utc_now()
    Repo.delete_all(from g in ReviewGrant, where: g.expires_at <= ^now)
  end

  defp identity(project, grant) do
    with true <- DateTime.compare(grant.expires_at, DateTime.utc_now()) == :gt,
         true <- grant.credential_version == project.credential_version,
         %Account{} = account <- Repo.get(Account, grant.account_id),
         true <- live_session?(grant, account),
         true <- member?(account, project) do
      if Accounts.private_feedback_only?() do
        case Repo.get(Fluently.Accounts.User, account.user_id) do
          %Fluently.Accounts.User{} = user ->
            {:ok,
             %Actor{
               project_id: project.id,
               user_id: user.id,
               name: user.name || account.name || "Account user",
               email: user.email || account.email
             }}

          _ ->
            {:error, :unauthorized}
        end
      else
        with %ProjectAdmin{} = member <- Repo.get(ProjectAdmin, grant.membership_id),
             true <-
               member.project_id == project.id and member.workspace_id == account.workspace_id,
             %ProjectUser{} = user <- Repo.get(ProjectUser, member.reviewer_id),
             true <- user.project_id == project.id and user.user_id == account.user_id do
          {:ok, %{user | account_member: true}}
        else
          _ -> {:error, :unauthorized}
        end
      end
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp live_account?(%Account{email: email, session_hash: hash, session_expires_at: expires})
       when not is_nil(email) and not is_nil(hash) and not is_nil(expires),
       do: DateTime.compare(expires, DateTime.utc_now()) == :gt

  defp live_account?(_), do: false

  defp live_session?(%ReviewGrant{account_session_id: session_id}, %Account{} = account)
       when is_binary(session_id) do
    case Repo.get(AccountSession, session_id) do
      %AccountSession{account_id: account_id, user_id: user_id, expires_at: expires_at}
      when account_id == account.id and user_id == account.user_id ->
        DateTime.compare(expires_at, DateTime.utc_now()) == :gt

      _ ->
        false
    end
  end

  defp live_session?(%ReviewGrant{account_session_id: nil, account_session_hash: hash}, account),
    do: live_account?(account) and account.session_hash == hash
end
