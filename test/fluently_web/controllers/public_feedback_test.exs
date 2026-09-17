defmodule FluentlyWeb.PublicFeedbackTest do
  use FluentlyWeb.ConnCase, async: false
  alias Fluently.{Accounts, Feedback, Repo, Threads, ProjectAccess}
  import Fluently.FeedbackFixtures

  setup do
    {:ok, workspace, key} = Feedback.create_workspace("Fluently")

    {:ok, project, keys} =
      Feedback.create_project(workspace, %{name: "Fluently", origin: "http://localhost"})

    project = Repo.update!(Ecto.Changeset.change(project, public_feedback: true))
    previous = Application.get_env(:fluently, :feedback_project_id)
    Application.put_env(:fluently, :feedback_project_id, project.id)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:fluently, :feedback_project_id, previous),
        else: Application.delete_env(:fluently, :feedback_project_id)
    end)

    %{project: project, workspace: workspace, key: key, keys: keys}
  end

  defp visitor do
    n = System.unique_integer([:positive])

    %{build_conn() | host: "localhost", remote_ip: {10, 12, rem(div(n, 256), 256), rem(n, 256)}}
    |> put_req_header("content-type", "application/json")
  end

  defp next(conn), do: conn |> recycle() |> put_req_header("content-type", "application/json")
  defp comment, do: visitor() |> post("/demo/comments", attrs())
  defp account(conn), do: Accounts.current(get_session(conn, :account_token))

  defp register(email) do
    {:ok, {account, token}} =
      Accounts.register(nil, %{
        name: "Team member",
        email: email,
        password: "long enough passphrase"
      })

    {account, token}
  end

  test "shared project, private visitor threads and snapshots, all endpoint boundaries", %{
    project: p
  } do
    first = comment()
    thread = json_response(first, 201)["data"]
    second = comment()
    other = json_response(second, 201)["data"]
    assert thread["project_id"] == p.id
    assert other["project_id"] == p.id
    assert is_nil(account(first).demo_project_id)
    assert length(Threads.list(p, %{})) == 2
    assert visitor() |> get("/demo/comments") |> json_response(200) |> Map.fetch!("data") == []
    listed = first |> next() |> get("/demo/comments") |> json_response(200)
    assert Enum.map(listed["data"], & &1["id"]) == [thread["id"]]
    path = "/demo/comments/#{thread["id"]}"

    assert first
           |> next()
           |> post(path <> "/snapshot", %{data_url: snapshot()})
           |> json_response(200)

    for client <- [second, visitor()] do
      assert client |> next() |> get(path <> "/snapshot") |> json_response(404)

      assert client
             |> next()
             |> post(path <> "/snapshot", %{data_url: snapshot()})
             |> json_response(404)

      assert client
             |> next()
             |> post(path <> "/replies", %{body: "intrusion"})
             |> json_response(404)

      assert client |> next() |> patch(path, %{status: "resolved"}) |> json_response(404)

      assert client
             |> next()
             |> delete(path <> "/messages/" <> hd(thread["messages"])["id"])
             |> json_response(404)
    end

    assert first |> next() |> patch(path, %{status: "resolved"}) |> json_response(200)

    assert first
           |> next()
           |> delete(path <> "/messages/" <> hd(thread["messages"])["id"])
           |> json_response(200)

    assert Threads.get(p, other["id"])
  end

  test "owner and explicit admin inbox, reply visibility and revocation", %{
    project: p,
    workspace: w,
    key: key
  } do
    first = comment()
    thread = json_response(first, 201)["data"]
    second = comment()
    other = json_response(second, 201)["data"]
    owner = visitor() |> post("/app/login", %{key: key})
    path = "/app/projects/#{p.id}"
    snapshot_path = "/demo/comments/#{thread["id"]}/snapshot"
    assert first |> next() |> post(snapshot_path, %{data_url: snapshot()}) |> json_response(200)

    assert owner
           |> next()
           |> get("/demo/comments")
           |> json_response(200)
           |> Map.fetch!("data")
           |> length() == 2

    assert owner |> next() |> get(path <> "/threads/#{thread["id"]}/snapshot") |> response(200)

    doc = owner |> next() |> get(path) |> html_response(200) |> LazyHTML.from_document()
    assert Enum.any?(LazyHTML.query(doc, "#reply-#{thread["id"]}"))
    assert Enum.any?(LazyHTML.query(doc, "#reply-#{other["id"]}"))

    assert owner
           |> next()
           |> post(path <> "/threads/#{thread["id"]}/replies", %{body: "Thanks, fixing this!"})
           |> redirected_to() == path

    data = first |> next() |> get("/demo/comments") |> json_response(200)
    assert List.last(hd(data["data"])["messages"])["body"] == "Thanks, fixing this!"
    data = second |> next() |> get("/demo/comments") |> json_response(200)
    assert length(hd(data["data"])["messages"]) == 1
    {admin, token} = register("admin@example.com")
    admin_conn = visitor() |> init_test_session(account_token: token)
    assert admin_conn |> get(path <> "/threads/#{thread["id"]}/snapshot") |> response(404)
    assert admin_conn |> get(path) |> response(404)

    assert owner |> next() |> post(path <> "/admins", %{email: admin.email}) |> redirected_to() ==
             path

    doc = admin_conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
    refute Enum.any?(LazyHTML.query(doc, "#rotate-credentials"))
    assert Enum.any?(LazyHTML.query(doc, "#reply-#{thread["id"]}"))

    assert admin_conn
           |> get("/demo/comments")
           |> json_response(200)
           |> Map.fetch!("data")
           |> length() == 2

    assert admin_conn
           |> post("/demo/comments/#{thread["id"]}/replies", %{body: "Admin reply on website"})
           |> json_response(200)

    assert admin_conn
           |> post(path <> "/threads/#{thread["id"]}/status", %{status: "resolved"})
           |> redirected_to() == path

    assert admin_conn |> post(path <> "/rotate") |> response(404)
    assert admin_conn |> post(path <> "/delete", %{confirm: "delete"}) |> response(404)
    assert admin_conn |> post(path <> "/admins", %{email: admin.email}) |> response(422)

    messages =
      admin_conn
      |> get("/demo/comments")
      |> json_response(200)
      |> Map.fetch!("data")
      |> hd()
      |> Map.fetch!("messages")

    admin_message = List.last(messages)
    assert admin_message["can_delete"]

    assert admin_conn
           |> delete("/demo/comments/#{thread["id"]}/messages/#{admin_message["id"]}")
           |> json_response(200)

    [membership] = ProjectAccess.admins(p)
    assert :ok = ProjectAccess.revoke(w, p.id, membership.id)
    assert admin_conn |> get(path) |> response(404)
    assert admin_conn |> get("/demo/comments") |> json_response(200) |> Map.fetch!("data") == []
  end

  test "signup retains reviewer; guest expiry retains owner feedback", %{project: p} do
    first = comment()
    a = account(first)

    {:ok, {registered, _}} =
      Accounts.register(a, %{
        name: "Jamie",
        email: "jamie@example.com",
        password: "long enough passphrase"
      })

    assert registered.feedback_reviewer_id == a.feedback_reviewer_id
    assert is_nil(registered.expires_at)
    second = comment()
    b = account(second)
    Repo.update!(Ecto.Changeset.change(b, expires_at: DateTime.add(DateTime.utc_now(), -1, :day)))
    assert {:ok, 1} = Accounts.prune_expired()
    assert length(Threads.list(p, %{})) == 2
    assert Repo.get(Fluently.Feedback.Reviewer, b.feedback_reviewer_id)
    assert is_nil(Repo.get(Fluently.Accounts.Account, b.id))
  end

  test "invite tokens cannot bypass visitor visibility; owner read key can see all", %{
    project: p,
    keys: keys
  } do
    first = comment()
    thread = json_response(first, 201)["data"]
    {:ok, token, _} = Feedback.start_review(p, keys.review, "Invited guest")
    client = visitor() |> put_req_header("authorization", "Bearer " <> token)
    path = "/api/projects/#{p.id}/comments"
    assert client |> get(path) |> json_response(200) |> Map.fetch!("data") == []
    assert client |> get(path <> "/" <> thread["id"]) |> json_response(404)
    assert client |> get(path <> "/#{thread["id"]}/snapshot") |> json_response(404)

    assert client
           |> post(path <> "/#{thread["id"]}/replies", %{body: "intrusion"})
           |> json_response(404)

    assert client
           |> patch(path <> "/#{thread["id"]}", %{status: "resolved"})
           |> json_response(404)

    assert client
           |> delete(path <> "/#{thread["id"]}/messages/" <> hd(thread["messages"])["id"])
           |> json_response(404)

    reader = visitor() |> put_req_header("authorization", "Bearer " <> keys.api)
    assert reader |> get(path) |> json_response(200) |> Map.fetch!("data") |> length() == 1

    assert reader
           |> patch(path <> "/#{thread["id"]}", %{status: "resolved"})
           |> json_response(403)
  end

  test "previously private demo is never shared when switching to owner feedback", %{project: p} do
    Application.delete_env(:fluently, :feedback_project_id)
    legacy = comment()
    a = account(legacy)
    old = json_response(legacy, 201)["data"]
    Application.put_env(:fluently, :feedback_project_id, p.id)
    fresh = legacy |> next() |> post("/demo/comments", attrs())
    assert json_response(fresh, 201)["data"]["project_id"] == p.id
    assert account(fresh).demo_project_id == a.demo_project_id
    assert Threads.get(Feedback.project(a.demo_project_id), old["id"])
    assert length(Threads.list(p, %{})) == 1
  end

  test "missing or unapproved configured project fails closed", %{project: p} do
    Repo.update!(Ecto.Changeset.change(p, public_feedback: false))
    assert comment() |> json_response(422)
    assert Repo.aggregate(Fluently.Accounts.Account, :count) == 0
  end
end
