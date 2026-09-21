defmodule FluentlyWeb.CustomerReferenceTest do
  use FluentlyWeb.ConnCase, async: false
  alias Fluently.{Feedback, Repo}
  alias Fluently.Projects.ProjectUser
  import Fluently.FeedbackFixtures

  setup do
    {:ok, workspace, _} = Feedback.create_workspace("Studio")

    {:ok, project, keys} =
      Feedback.create_project(workspace, %{name: "Site", origin: "https://example.com"})

    %{workspace: workspace, project: project, keys: keys}
  end

  defp api(project, token) do
    build_conn()
    |> put_req_header("origin", project.origin)
    |> put_req_header("authorization", "Bearer " <> token)
  end

  test "references are project-local unverified attribution, never shared with guest readers",
       c do
    session =
      build_conn()
      |> put_req_header("origin", c.project.origin)
      |> post("/api/projects/#{c.project.id}/sessions", %{
        token: c.keys.review,
        name: "Guest",
        external_ref: "opaque-hmac"
      })
      |> json_response(200)

    user = Repo.get!(ProjectUser, session["reviewer"]["id"])
    assert user.external_id == "opaque-hmac"
    assert user.kind == "pseudonymous"

    guest =
      api(c.project, session["token"])
      |> post(
        "/api/projects/#{c.project.id}/comments",
        Map.put(attrs(), "external_ref", "cannot-overwrite")
      )
      |> json_response(201)

    refute hd(guest["data"]["messages"])["author"]["external_ref"]

    owner =
      api(c.project, c.keys.api)
      |> get("/api/projects/#{c.project.id}/comments")
      |> json_response(200)

    author = hd(hd(owner["data"])["messages"])["author"]

    assert author["external_ref"] == %{
             "value" => "opaque-hmac",
             "verified" => false,
             "scope" => c.project.id
           }

    {:ok, another, _} = Feedback.start_review(c.project, c.keys.review, "Other guest")

    response =
      api(c.project, another)
      |> get("/api/projects/#{c.project.id}/comments")
      |> json_response(200)

    refute hd(hd(response["data"])["messages"])["author"]["external_ref"]
    assert response["identity"] == %{"name" => "Other guest", "kind" => "guest"}

    {:ok, {account, _}} =
      Fluently.Accounts.register(nil, %{
        name: "Admin",
        email: "admin@example.test",
        password: "a sufficiently long password"
      })

    {:ok, _} = Fluently.ProjectAccess.grant(c.workspace, c.project.id, account.email)
    verifier = Feedback.secret()
    challenge = Base.url_encode64(Feedback.hash(verifier), padding: false)
    {:ok, code} = Fluently.AccountReviews.issue(c.project, account, challenge)

    connected =
      build_conn()
      |> put_req_header("origin", c.project.origin)
      |> post("/api/projects/#{c.project.id}/account-sessions", %{
        code: code,
        verifier: verifier,
        external_ref: "must-not-link-account"
      })
      |> json_response(200)

    assert Repo.get!(ProjectUser, connected["reviewer"]["id"]).external_id == nil

    member =
      api(c.project, connected["token"])
      |> get("/api/projects/#{c.project.id}/comments")
      |> json_response(200)

    assert hd(hd(member["data"])["messages"])["author"]["external_ref"] == author["external_ref"]
  end

  test "same reference never merges identities or unlocks old private threads", c do
    public = Repo.update!(Ecto.Changeset.change(c.project, public_feedback: true))
    {:ok, first_token, first} = Feedback.start_review(public, c.keys.review, "One", "same-ref")
    {:ok, second_token, second} = Feedback.start_review(public, c.keys.review, "Two", "same-ref")
    refute first.id == second.id
    refute first.user_id == second.user_id

    api(public, first_token)
    |> post("/api/projects/#{public.id}/comments", attrs())
    |> json_response(201)

    assert api(public, second_token)
           |> get("/api/projects/#{public.id}/comments")
           |> json_response(200)
           |> Map.fetch!("data") == []

    assert {:error, :unauthorized} =
             Feedback.start_review(public, "same-ref", "Imposter", "same-ref")

    assert {:error, :unauthorized} = Feedback.authorize(public, "same-ref")

    {:ok, other, keys} =
      Feedback.create_project(c.workspace, %{name: "Other", origin: public.origin})

    {:ok, _, third} = Feedback.start_review(other, keys.review, "Three", "same-ref")
    refute third.user_id == first.user_id
    assert third.project_id == other.id
    assert {:error, :unauthorized} = Feedback.authorize(other, first_token)
  end

  test "references are bounded and optional, and malformed values create no identities", c do
    baseline = Repo.aggregate(ProjectUser, :count)

    for value <- [
          "",
          String.duplicate("a", 201),
          "with spaces",
          "mail@example.com",
          "new\nline",
          %{},
          123
        ] do
      result =
        build_conn()
        |> post("/api/projects/#{c.project.id}/sessions", %{
          token: c.keys.review,
          name: "Guest",
          external_ref: value
        })

      assert json_response(result, 422)
    end

    assert Repo.aggregate(ProjectUser, :count) == baseline

    assert {:ok, _, %{external_id: nil, kind: "guest"}} =
             Feedback.start_review(c.project, c.keys.review, "Guest")

    assert {:ok, _, _} =
             Feedback.start_review(c.project, c.keys.review, "Guest", String.duplicate("a", 200))
  end
end
