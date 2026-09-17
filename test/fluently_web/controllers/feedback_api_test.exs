defmodule FluentlyWeb.FeedbackAPITest do
  use FluentlyWeb.ConnCase, async: true
  alias Fluently.Feedback

  setup do
    {:ok, owner, _} = Feedback.create_workspace("API")

    {:ok, project, keys} =
      Feedback.create_project(owner, %{"name" => "Site", "origin" => "https://example.com"})

    {:ok, token, reviewer} = Feedback.start_review(project, keys.review, "API guest")

    %{
      project: project,
      keys: keys,
      token: token,
      reviewer: reviewer,
      path: "/api/projects/#{project.id}"
    }
  end

  defp api(token, origin \\ "https://example.com") do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("origin", origin)
    |> put_req_header("content-type", "application/json")
  end

  test "public snippet ID grants neither reads nor writes", ctx do
    assert build_conn() |> get(ctx.path <> "/comments") |> json_response(401)
    assert api(ctx.project.id) |> post(ctx.path <> "/comments", %{}) |> json_response(401)
    assert api(ctx.keys.review) |> get(ctx.path <> "/comments") |> json_response(401)
  end

  test "origin checks and CORS preflight are explicit", ctx do
    assert api(ctx.token, "https://evil.test")
           |> get(ctx.path <> "/comments")
           |> json_response(403)

    conn =
      build_conn()
      |> put_req_header("origin", "https://example.com")
      |> options(ctx.path <> "/comments")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "access-control-allow-origin") == ["https://example.com"]
    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end

  test "guest exchange and full API lifecycle", ctx do
    session =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(ctx.path <> "/sessions", %{token: ctx.keys.review, name: "Guest"})
      |> json_response(200)

    token = session["token"]

    result =
      api(token)
      |> post(ctx.path <> "/comments", Fluently.FeedbackFixtures.attrs())
      |> json_response(201)

    id = result["data"]["id"]

    assert api(token)
           |> post(ctx.path <> "/comments/#{id}/replies", %{body: "Reply"})
           |> json_response(200)

    assert api(token)
           |> patch(ctx.path <> "/comments/#{id}", %{status: "resolved"})
           |> json_response(200)

    result =
      api(ctx.keys.api) |> get(ctx.path <> "/comments?status=resolved") |> json_response(200)

    assert length(result["data"]) == 1
    assert length(hd(result["data"])["messages"]) == 2
    assert api(ctx.keys.api) |> post(ctx.path <> "/comments", %{}) |> json_response(403)

    assert api(token)
           |> patch(ctx.path <> "/comments/#{id}", %{status: "garbage"})
           |> json_response(422)
  end

  test "wrong project session and thread IDs cannot leak data", ctx do
    {:ok, owner, _} = Feedback.create_workspace("Other")

    {:ok, p, _} =
      Feedback.create_project(owner, %{"name" => "Other", "origin" => "https://example.com"})

    assert api(ctx.token) |> get("/api/projects/#{p.id}/comments") |> json_response(401)

    assert api(ctx.token)
           |> get(ctx.path <> "/comments/#{Ecto.UUID.generate()}")
           |> json_response(404)

    assert api(ctx.token) |> get("/api/projects/not-a-uuid/comments") |> json_response(404)
  end

  test "rate limiting rejects requests after the limit" do
    key = {:test, Ecto.UUID.generate()}
    assert Fluently.RateLimit.allow?(key, 2)
    assert Fluently.RateLimit.allow?(key, 2)
    refute Fluently.RateLimit.allow?(key, 2)
  end

  test "API write limits apply at the request boundary", ctx do
    for _ <- 1..40 do
      assert api(ctx.token) |> post(ctx.path <> "/comments", %{}) |> json_response(422)
    end

    assert api(ctx.token) |> post(ctx.path <> "/comments", %{}) |> json_response(429)
    assert api(ctx.token) |> get(ctx.path <> "/comments") |> json_response(200)
  end

  test "authors can delete replies and their threads, with project-scoped authorization", ctx do
    thread =
      api(ctx.token)
      |> post(ctx.path <> "/comments", Fluently.FeedbackFixtures.attrs())
      |> json_response(201)
      |> Map.fetch!("data")

    first = hd(thread["messages"])
    assert first["can_delete"]
    path = ctx.path <> "/comments/#{thread["id"]}/messages/#{first["id"]}"
    {:ok, other_token, _} = Feedback.start_review(ctx.project, ctx.keys.review, "Other guest")
    view = api(other_token) |> get(ctx.path <> "/comments/#{thread["id"]}") |> json_response(200)
    refute hd(view["data"]["messages"])["can_delete"]
    assert api(other_token) |> delete(path) |> json_response(404)
    assert api(ctx.keys.api) |> delete(path) |> json_response(403)
    assert build_conn() |> delete(path) |> json_response(401)
    assert api(ctx.token, "https://evil.test") |> delete(path) |> json_response(403)

    replied =
      api(other_token)
      |> post(ctx.path <> "/comments/#{thread["id"]}/replies", %{body: "My reply"})
      |> json_response(200)

    reply = List.last(replied["data"]["messages"])
    assert reply["can_delete"]
    reply_path = ctx.path <> "/comments/#{thread["id"]}/messages/#{reply["id"]}"
    assert api(ctx.token) |> delete(reply_path) |> json_response(404)
    result = api(other_token) |> delete(reply_path) |> json_response(200)
    refute result["deleted_thread"]
    assert length(result["data"]["messages"]) == 1
    assert api(other_token) |> delete(reply_path) |> json_response(404)

    replied =
      api(other_token)
      |> post(ctx.path <> "/comments/#{thread["id"]}/replies", %{body: "Another reply"})
      |> json_response(200)

    remaining_reply = List.last(replied["data"]["messages"])
    result = api(ctx.token) |> delete(path) |> json_response(200)
    assert result["deleted_thread"]
    assert is_nil(result["data"])
    assert api(ctx.token) |> get(ctx.path <> "/comments/#{thread["id"]}") |> json_response(404)
    assert is_nil(Fluently.Repo.get(Fluently.Feedback.Message, remaining_reply["id"]))
    assert api(ctx.token) |> delete(path) |> json_response(404)
  end

  test "message deletion rejects mismatched threads and project credentials", ctx do
    {:ok, one} =
      Fluently.Threads.create(ctx.project, ctx.reviewer, Fluently.FeedbackFixtures.attrs())

    {:ok, two} =
      Fluently.Threads.create(ctx.project, ctx.reviewer, Fluently.FeedbackFixtures.attrs())

    path = ctx.path <> "/comments/#{two.id}/messages/#{hd(one.messages).id}"
    assert api(ctx.token) |> delete(path) |> json_response(404)

    assert api(ctx.token)
           |> delete(ctx.path <> "/comments/invalid/messages/invalid")
           |> json_response(404)

    {:ok, owner, _} = Feedback.create_workspace("Another tenant")

    {:ok, project, keys} =
      Feedback.create_project(owner, %{"name" => "Other", "origin" => "https://example.com"})

    {:ok, token, _} = Feedback.start_review(project, keys.review, "Other tenant")

    assert api(token)
           |> delete(ctx.path <> "/comments/#{one.id}/messages/#{hd(one.messages).id}")
           |> json_response(401)

    assert Fluently.Threads.get(ctx.project, one.id)
    assert Fluently.Threads.get(ctx.project, two.id)
  end
end
