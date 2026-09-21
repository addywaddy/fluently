defmodule Fluently.InvitationsTest do
  use Fluently.DataCase, async: false

  alias Fluently.{Accounts, Feedback, Invitations, Repo}
  alias Fluently.Accounts.{AccountMembership, Invitation}
  alias Fluently.Projects.{ProjectAdmin, ProjectMembership}

  setup do
    {:ok, {owner, _}} =
      Accounts.register(nil, %{
        name: "Owner",
        email: "invite-owner@example.test",
        password: "long enough owner password"
      })

    {:ok, {invitee, _}} =
      Accounts.register(nil, %{
        name: "Invitee",
        email: "invitee@example.test",
        password: "long enough invitee password"
      })

    workspace = Feedback.workspace(owner.workspace_id)

    {:ok, project, _} =
      Feedback.create_project(workspace, %{name: "Checkout", origin: "https://example.test"})

    %{owner: owner, invitee: invitee, project: project}
  end

  test "issues and atomically accepts a project-scoped invitation", c do
    {:ok, invitation, token} =
      Invitations.issue(c.owner, c.owner.user_id, c.invitee.email, [c.project.id])

    assert Invitation.active?(invitation)

    assert {:ok, accepted} = Invitations.accept(token, c.invitee.user_id)
    assert accepted.accepted_at

    assert Repo.get_by(AccountMembership, account_id: c.owner.id, user_id: c.invitee.user_id)
    assert Repo.get_by(ProjectMembership, project_id: c.project.id, user_id: c.invitee.user_id)

    assert Repo.get_by(ProjectAdmin,
             project_id: c.project.id,
             workspace_id: c.invitee.workspace_id
           )
  end

  test "wrong email and replayed or revoked invitations do not grant access", c do
    {:ok, _invitation, token} =
      Invitations.issue(c.owner, c.owner.user_id, c.invitee.email, [c.project.id])

    assert {:error, :unauthorized} = Invitations.accept(token, c.owner.user_id)
    assert {:ok, _} = Invitations.accept(token, c.invitee.user_id)
    assert {:error, :unauthorized} = Invitations.accept(token, c.invitee.user_id)

    {:ok, invitation, revoked_token} =
      Invitations.issue(c.owner, c.owner.user_id, c.invitee.email, [])

    assert {:ok, _} = Invitations.revoke(invitation)
    assert {:error, :unauthorized} = Invitations.accept(revoked_token, c.invitee.user_id)
  end

  test "non-admins and foreign projects cannot issue invitations", c do
    assert {:error, :unauthorized} =
             Invitations.issue(c.invitee, c.invitee.user_id, c.owner.email, [c.project.id])

    {:ok, other_workspace, _} = Feedback.create_workspace("Other")

    {:ok, other_project, _} =
      Feedback.create_project(other_workspace, %{
        name: "Other",
        origin: "https://other.example.test"
      })

    assert {:error, :unauthorized} =
             Invitations.issue(c.owner, c.owner.user_id, c.invitee.email, [other_project.id])
  end
end
