defmodule FluentlyWeb.InvitationControllerTest do
  use FluentlyWeb.ConnCase, async: false

  alias Fluently.{Accounts, Feedback, Invitations, Repo}
  alias Fluently.Accounts.{AccountMembership, Invitation}

  setup do
    {:ok, {owner, owner_token}} =
      Accounts.register(nil, %{
        name: "Owner",
        email: "controller-owner@example.test",
        password: "long enough owner password"
      })

    {:ok, {invitee, invitee_token}} =
      Accounts.register(nil, %{
        name: "Invitee",
        email: "controller-invitee@example.test",
        password: "long enough invitee password"
      })

    workspace = Feedback.workspace(owner.workspace_id)

    {:ok, project, _} =
      Feedback.create_project(workspace, %{name: "Checkout", origin: "https://example.test"})

    %{
      owner: owner,
      owner_token: owner_token,
      invitee: invitee,
      invitee_token: invitee_token,
      project: project
    }
  end

  test "unauthenticated visitors are sent to login and the token survives login", c do
    {:ok, _invitation, token} =
      Invitations.issue(c.owner, c.owner.user_id, c.invitee.email, [c.project.id])

    conn = build_conn() |> get("/invitations/#{token}")
    assert redirected_to(conn) == "/login"
    assert get_session(conn, :invitation_token) == token
  end

  test "the invited user can accept after signing in", c do
    {:ok, _invitation, token} =
      Invitations.issue(c.owner, c.owner.user_id, c.invitee.email, [c.project.id])

    conn =
      build_conn()
      |> init_test_session(account_token: c.invitee_token)
      |> get("/invitations/#{token}")

    assert html_response(conn, 200) =~ "Accept invitation"

    accepted = conn |> recycle() |> post("/invitations/#{token}")
    assert redirected_to(accepted) == "/app"
    assert Repo.get_by(AccountMembership, account_id: c.owner.id, user_id: c.invitee.user_id)
  end

  test "a different signed-in user cannot accept the invitation", c do
    {:ok, _invitation, token} =
      Invitations.issue(c.owner, c.owner.user_id, c.invitee.email, [c.project.id])

    conn =
      build_conn()
      |> init_test_session(account_token: c.owner_token)
      |> get("/invitations/#{token}")

    assert response(conn, 422) =~ "belongs to another email"
    refute Repo.get_by(AccountMembership, account_id: c.owner.id, user_id: c.owner.user_id) == nil
  end

  test "owner dashboard sends an invitation", c do
    conn =
      build_conn()
      |> init_test_session(account_token: c.owner_token)
      |> post("/app/projects/#{c.project.id}/invitations", %{email: c.invitee.email})

    assert redirected_to(conn) == "/app/projects/#{c.project.id}"
    assert Repo.aggregate(Invitation, :count) == 1
  end
end
