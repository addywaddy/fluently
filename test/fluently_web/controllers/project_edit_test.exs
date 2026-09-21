defmodule FluentlyWeb.ProjectEditTest do
  use FluentlyWeb.ConnCase, async: false
  alias Fluently.{Feedback, Repo}
  alias Fluently.Feedback.ProjectAdmin

  test "origin changes revoke account review grants while name changes preserve them" do
    {:ok, {account, _}} =
      Fluently.Accounts.register(nil, %{
        name: "Owner",
        email: "project-edit@example.com",
        password: "long-enough-password"
      })

    workspace = Feedback.workspace(account.workspace_id)

    {:ok, project, _} =
      Feedback.create_project(workspace, %{name: "Site", origin: "https://example.com"})

    verifier = Feedback.secret()
    challenge = Base.url_encode64(Feedback.hash(verifier), padding: false)
    {:ok, code} = Fluently.AccountReviews.issue(project, account, challenge)
    {:ok, grant} = Fluently.AccountReviews.exchange(project, code, verifier)
    {:ok, {renamed, nil}} = Feedback.update_project(workspace, project.id, %{name: "Renamed"})
    assert {:ok, _} = Fluently.AccountReviews.authorize(renamed, grant.token)

    {:ok, {moved, _}} =
      Feedback.update_project(workspace, project.id, %{origin: "https://staging.example.com"})

    assert {:error, :unauthorized} = Fluently.AccountReviews.authorize(moved, grant.token)
  end

  setup do
    {:ok, workspace, key} = Feedback.create_workspace("Studio")

    {:ok, project, credentials} =
      Feedback.create_project(workspace, %{name: "Checkout", origin: "https://example.com"})

    conn = build_conn() |> post("/app/login", %{key: key}) |> recycle()
    %{conn: conn, workspace: workspace, project: project, credentials: credentials}
  end

  test "owner can edit the name without changing credentials or protected fields", ctx do
    path = "/app/projects/#{ctx.project.id}"
    doc = ctx.conn |> get(path <> "/edit") |> html_response(200) |> LazyHTML.from_document()
    assert Enum.any?(LazyHTML.query(doc, ~s(#edit-project input[name="_csrf_token"])))
    assert Enum.any?(LazyHTML.query(doc, ~s(#edit-project input[value="Checkout"])))
    assert Enum.any?(LazyHTML.query(doc, "#cancel-project-edit"))

    conn =
      patch(ctx.conn, path, %{
        project: %{
          name: "New checkout",
          origin: ctx.project.origin,
          workspace_id: Ecto.UUID.generate(),
          public_feedback: true,
          credential_version: 900
        }
      })

    assert redirected_to(conn) == path
    updated = Feedback.project(ctx.project.id)
    assert updated.name == "New checkout"
    assert updated.workspace_id == ctx.workspace.id
    refute updated.public_feedback
    assert updated.credential_version == ctx.project.credential_version
    assert updated.api_hash == ctx.project.api_hash
    assert updated.review_hash == ctx.project.review_hash
    doc = conn |> recycle() |> get(path) |> html_response(200) |> LazyHTML.from_document()
    assert Enum.any?(LazyHTML.query(doc, "#project-notice"))
  end

  test "invalid changes retain input and leave the project and credentials unchanged", ctx do
    for origin <- [
          "https://example.com/path",
          "http://example.com",
          "https://example.com?secret=x",
          ""
        ] do
      conn =
        patch(ctx.conn, "/app/projects/#{ctx.project.id}", %{
          project: %{name: "Attempt", origin: origin}
        })

      doc = conn |> html_response(422) |> LazyHTML.from_document()
      assert Enum.any?(LazyHTML.query(doc, ~s(#edit-project input[value="Attempt"])))
      assert Feedback.project(ctx.project.id) == ctx.project
    end

    assert {:error, %Ecto.Changeset{}} =
             Feedback.update_project(ctx.workspace, ctx.project.id, %{name: " "})

    assert {:error, %Ecto.Changeset{}} =
             Feedback.update_project(ctx.workspace, ctx.project.id, %{
               name: String.duplicate("x", 101)
             })
  end

  test "origin changes invalidate old credentials and sessions and show replacement keys once",
       ctx do
    {:ok, token, reviewer} =
      Feedback.start_review(ctx.project, ctx.credentials.review, "Reviewer")

    {:ok, thread} =
      Fluently.Threads.create(ctx.project, reviewer, Fluently.FeedbackFixtures.attrs())

    path = "/app/projects/#{ctx.project.id}"

    conn =
      patch(ctx.conn, path, %{project: %{origin: "http://localhost:4100", name: "Local checkout"}})

    assert redirected_to(conn) == path
    updated = Feedback.project(ctx.project.id)
    assert updated.origin == "http://localhost:4100"
    assert updated.credential_version == ctx.project.credential_version + 1
    refute Feedback.valid_secret?(ctx.credentials.api, updated.api_hash)

    assert {:error, :unauthorized} =
             Feedback.start_review(updated, ctx.credentials.review, "Reviewer")

    assert {:error, :unauthorized} = Feedback.authorize(updated, token)
    assert Repo.get!(Fluently.Feedback.Thread, thread.id).page == thread.page
    conn = conn |> recycle() |> get(path)
    doc = conn |> html_response(200) |> LazyHTML.from_document()
    assert Enum.any?(LazyHTML.query(doc, ~s(a[href^="http://localhost:4100/#fluently="])))
    doc = conn |> recycle() |> get(path) |> html_response(200) |> LazyHTML.from_document()
    refute Enum.any?(LazyHTML.query(doc, ~s(a[href*="#fluently="])))
  end

  test "other workspaces and invited admins cannot edit; anonymous users must log in", ctx do
    path = "/app/projects/#{ctx.project.id}"
    {:ok, other, key} = Feedback.create_workspace("Other")
    conn = build_conn() |> post("/app/login", %{key: key}) |> recycle()

    for admin <- [false, true] do
      if admin,
        do: Repo.insert!(%ProjectAdmin{project_id: ctx.project.id, workspace_id: other.id})

      assert conn |> get(path <> "/edit") |> response(404)
      assert conn |> patch(path, %{project: %{name: "Stolen"}}) |> response(404)

      assert {:error, :not_found} =
               Feedback.update_project(other, ctx.project.id, %{name: "Stolen"})
    end

    doc = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
    refute Enum.any?(LazyHTML.query(doc, "#edit-project-link"))
    assert build_conn() |> get(path <> "/edit") |> redirected_to() == "/app/login"

    assert build_conn() |> patch(path, %{project: %{name: "Stolen"}}) |> redirected_to() ==
             "/app/login"

    assert Feedback.project(ctx.project.id) == ctx.project
  end
end
