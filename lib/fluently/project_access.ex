defmodule Fluently.ProjectAccess do
  @moduledoc "Explicit project administration. Credentials and membership changes remain owner-only."
  import Ecto.Query
  alias Fluently.{Repo, Feedback}
  alias Fluently.Feedback.{Project, ProjectAdmin, ProjectMembership, ProjectUser}
  alias Fluently.Accounts.{Account, AccountMembership}

  @doc """
  Returns whether an account's user may review a project.

  Owners and admins can review every project in their account. Ordinary
  members need an explicit project membership. The account membership check is
  deliberately independent of the legacy ProjectAdmin row so removing access
  takes effect even while compatibility rows remain.
  """
  def authorized?(%Account{user_id: user_id}, %Project{id: project_id})
      when is_binary(user_id) do
    Repo.exists?(
      from am in AccountMembership,
        join: owning_account in Account,
        on: owning_account.id == am.account_id,
        join: p in Project,
        on: p.id == ^project_id,
        where: am.user_id == ^user_id,
        where:
          (am.role in ["owner", "admin"] and p.workspace_id == owning_account.workspace_id) or
            exists(
              from pm in ProjectMembership,
                where: pm.project_id == ^project_id and pm.user_id == ^user_id
            )
    )
  end

  def authorized?(_, _), do: false

  def projects(workspace) do
    Repo.all(
      from p in Project,
        left_join: a in ProjectAdmin,
        on: a.project_id == p.id and a.workspace_id == ^workspace.id,
        where: p.workspace_id == ^workspace.id or not is_nil(a.id),
        order_by: [desc: p.inserted_at]
    )
  end

  def project(workspace, id) do
    with %Project{} = p <- Feedback.project(id),
         true <-
           p.workspace_id == workspace.id or
             Repo.exists?(
               from a in ProjectAdmin,
                 where: a.project_id == ^p.id and a.workspace_id == ^workspace.id
             ) do
      p
    else
      _ -> nil
    end
  end

  def admins(project) do
    Repo.all(
      from a in ProjectAdmin,
        join: u in Account,
        on: u.workspace_id == a.workspace_id,
        where: a.project_id == ^project.id and a.workspace_id != ^project.workspace_id,
        select: %{id: a.id, name: u.name, email: u.email}
    )
  end

  def grant(owner, id, email) when is_binary(email) do
    with %Project{} = p <- Feedback.project(owner, id),
         %Account{email: email} = account when not is_nil(email) <-
           Repo.get_by(Account, email: String.downcase(String.trim(email))) do
      account = Fluently.Accounts.ensure_user(account)

      Repo.transaction(fn ->
        {:ok, admin} =
          %ProjectAdmin{project_id: p.id, workspace_id: account.workspace_id}
          |> Repo.insert(on_conflict: :nothing, conflict_target: [:project_id, :workspace_id])

        %ProjectMembership{project_id: p.id, user_id: account.user_id}
        |> Ecto.Changeset.change()
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:project_id, :user_id])

        if owning_account = Repo.get_by(Account, workspace_id: p.workspace_id) do
          %Fluently.Accounts.AccountMembership{
            account_id: owning_account.id,
            user_id: account.user_id,
            role: "member"
          }
          |> Ecto.Changeset.change()
          |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :user_id])
        end

        admin
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  def grant(_, _, _), do: {:error, :not_found}

  def revoke(owner, id, admin_id) do
    with %Project{} = p <- Feedback.project(owner, id),
         {:ok, admin_id} <- Ecto.UUID.cast(admin_id) do
      Repo.transaction(fn ->
        admin =
          Repo.one(
            from a in ProjectAdmin,
              where: a.project_id == ^p.id and a.id == ^admin_id and a.workspace_id != ^owner.id
          )

        if admin do
          account =
            Repo.get_by(Account, workspace_id: admin.workspace_id)
            |> Fluently.Accounts.ensure_user()

          if account && account.user_id do
            Repo.delete_all(
              from pm in ProjectMembership,
                where: pm.project_id == ^p.id and pm.user_id == ^account.user_id
            )
          end

          Repo.delete!(admin)
        end
      end)

      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  def existing_reviewer(workspace, project) do
    if project(workspace, project.id) do
      case Repo.get_by(ProjectAdmin, project_id: project.id, workspace_id: workspace.id) do
        %{reviewer_id: id} when not is_nil(id) -> Repo.get(ProjectUser, id)
        _ -> nil
      end
    end
  end

  def reviewer(workspace, project) do
    Repo.transaction(fn ->
      if is_nil(project(workspace, project.id)), do: Repo.rollback(:not_found)
      membership = Repo.get_by(ProjectAdmin, project_id: project.id, workspace_id: workspace.id)

      if membership && membership.reviewer_id do
        identity = Repo.get!(ProjectUser, membership.reviewer_id)

        account =
          Repo.get_by(Account, workspace_id: workspace.id) |> Fluently.Accounts.ensure_user()

        if account && identity.user_id != account.user_id,
          do:
            identity
            |> Ecto.Changeset.change(
              user_id: account.user_id,
              name: account.name,
              kind: "account"
            )
            |> Repo.update!(),
          else: identity
      else
        account =
          Repo.get_by(Account, workspace_id: workspace.id) |> Fluently.Accounts.ensure_user()

        {:ok, reviewer} =
          Feedback.create_project_user(
            project,
            %{
              kind: if(account, do: "account", else: "admin"),
              name: if(account, do: account.name, else: "Project owner")
            },
            if(account, do: account.user_id, else: nil)
          )

        (membership || %ProjectAdmin{project_id: project.id, workspace_id: workspace.id})
        |> Ecto.Changeset.change(reviewer_id: reviewer.id)
        |> Repo.insert_or_update!()

        reviewer
      end
    end)
  end
end
