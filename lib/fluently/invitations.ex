defmodule Fluently.Invitations do
  @moduledoc "Issue and redeem account invitations."

  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]
  alias Fluently.{Feedback, Repo}
  alias Fluently.Accounts.{Account, AccountMembership, Invitation}
  alias Fluently.Feedback.{Project, ProjectAdmin, ProjectMembership}

  @expiry_days 7

  def issue(%Account{} = account, inviter_user_id, email, project_ids)
      when is_binary(inviter_user_id) and is_binary(email) and is_list(project_ids) do
    email = String.downcase(String.trim(email))
    project_ids = Enum.uniq(project_ids)

    with true <- inviter_authorized?(account.id, inviter_user_id),
         true <- valid_project_ids?(account.workspace_id, project_ids),
         true <- email_valid?(email) do
      token = Feedback.secret()

      attrs = %{
        account_id: account.id,
        invited_by_user_id: inviter_user_id,
        email: email,
        role: "member",
        project_ids: %{"ids" => project_ids},
        token_hash: Feedback.hash(token),
        expires_at: DateTime.add(DateTime.utc_now(), @expiry_days, :day)
      }

      case %Invitation{} |> Invitation.changeset(attrs) |> Repo.insert() do
        {:ok, invitation} -> {:ok, invitation, token}
        error -> error
      end
    else
      _ -> {:error, :unauthorized}
    end
  end

  def issue(_, _, _, _), do: {:error, :invalid}

  def accept(token, user_id) when is_binary(token) and is_binary(user_id) do
    Repo.transaction(fn ->
      invitation = Repo.get_by(Invitation, token_hash: Feedback.hash(token))
      user_account = Repo.get_by(Account, user_id: user_id)

      unless invitation && Invitation.active?(invitation) && user_account &&
               String.downcase(user_account.email || "") == invitation.email,
             do: Repo.rollback(:unauthorized)

      project_ids = get_in(invitation.project_ids, ["ids"]) || []

      Repo.insert!(
        %AccountMembership{
          account_id: invitation.account_id,
          user_id: user_id,
          role: invitation.role
        },
        on_conflict: :nothing,
        conflict_target: [:account_id, :user_id]
      )

      for project_id <- project_ids do
        Repo.insert!(
          %ProjectMembership{project_id: project_id, user_id: user_id},
          on_conflict: :nothing,
          conflict_target: [:project_id, :user_id]
        )

        Repo.insert!(
          %ProjectAdmin{project_id: project_id, workspace_id: user_account.workspace_id},
          on_conflict: :nothing,
          conflict_target: [:project_id, :workspace_id]
        )
      end

      invitation
      |> change(accepted_at: DateTime.utc_now())
      |> Repo.update!()
    end)
  end

  def accept(_, _), do: {:error, :unauthorized}

  def revoke(%Invitation{} = invitation) do
    invitation |> change(revoked_at: DateTime.utc_now()) |> Repo.update()
  end

  defp inviter_authorized?(account_id, user_id) do
    Repo.exists?(
      from m in AccountMembership,
        where:
          m.account_id == ^account_id and m.user_id == ^user_id and m.role in ["owner", "admin"]
    )
  end

  defp valid_project_ids?(workspace_id, project_ids) do
    count =
      Repo.aggregate(
        from(p in Project, where: p.workspace_id == ^workspace_id and p.id in ^project_ids),
        :count,
        :id
      )

    count == length(project_ids)
  end

  defp email_valid?(email), do: Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email)
end
