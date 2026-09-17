defmodule FluentlyWeb.DemoTest do
  use FluentlyWeb.ConnCase, async: false
  alias Fluently.{Accounts, Feedback, Repo, Threads}
  alias Fluently.Accounts.Account

  setup do
    previous = Application.get_env(:fluently, :dogfood_project_id)
    {:ok, workspace, _} = Feedback.create_workspace("Demo template")

    {:ok, template, keys} =
      Feedback.create_project(workspace, %{
        "name" => "Fluently",
        "origin" => "https://example.com"
      })

    Application.put_env(:fluently, :dogfood_project_id, template.id)
    on_exit(fn -> Application.put_env(:fluently, :dogfood_project_id, previous) end)
    %{template: template, keys: keys}
  end

  defp visitor do
    n = System.unique_integer([:positive])

    %{build_conn() | remote_ip: {10, div(n, 65536), rem(div(n, 256), 256), rem(n, 256)}}
    |> put_req_header("content-type", "application/json")
  end

  defp next(conn), do: conn |> recycle() |> put_req_header("content-type", "application/json")
  defp attrs, do: Fluently.FeedbackFixtures.attrs()

  defp signup_attrs,
    do: %{
      "account" => %{
        "name" => "Jamie",
        "email" => "jamie@example.com",
        "password" => "a long demo passphrase"
      }
    }

  test "visiting and invalid comments create no account; first successful comment creates one" do
    conn = visitor() |> get("/demo/comments")
    assert json_response(conn, 200)["data"] == []
    assert Repo.aggregate(Account, :count) == 0
    assert conn |> next() |> post("/demo/comments", %{}) |> json_response(422)
    assert Repo.aggregate(Account, :count) == 0
    conn = conn |> next() |> post("/demo/comments", attrs())
    result = json_response(conn, 201)["data"]
    assert result["page"] == "https://example.com/"
    assert hd(result["messages"])["author"]["kind"] == "anonymous"
    assert Repo.aggregate(Account, :count) == 1
    account = Accounts.current(get_session(conn, :account_token))
    assert account.demo_project_id == result["project_id"]
    assert conn.resp_cookies["_fluently_key"].http_only
  end

  test "cookie continuity, isolated visitors, replies and resolution", %{
    template: template,
    keys: keys
  } do
    first = visitor() |> post("/demo/comments", attrs())
    thread = json_response(first, 201)["data"]
    second = visitor() |> post("/demo/comments", attrs())
    other = json_response(second, 201)["data"]
    refute thread["project_id"] == other["project_id"]

    assert first
           |> next()
           |> get("/demo/comments")
           |> json_response(200)
           |> Map.get("data")
           |> length() == 1

    another = first |> next() |> post("/demo/comments", attrs()) |> json_response(201)

    assert hd(another["data"]["messages"])["author"]["id"] ==
             hd(thread["messages"])["author"]["id"]

    assert second
           |> next()
           |> post("/demo/comments/#{thread["id"]}/replies", %{body: "intrusion"})
           |> json_response(404)

    assert second
           |> next()
           |> patch("/demo/comments/#{thread["id"]}", %{status: "resolved"})
           |> json_response(404)

    assert visitor()
           |> patch("/demo/comments/#{thread["id"]}", %{status: "resolved"})
           |> json_response(404)

    assert first
           |> next()
           |> post("/demo/comments/#{thread["id"]}/replies", %{body: "follow up"})
           |> json_response(200)

    assert first
           |> next()
           |> patch("/demo/comments/#{thread["id"]}", %{status: "resolved"})
           |> json_response(200)

    data = first |> next() |> get("/demo/comments?status=resolved") |> json_response(200)
    assert length(data["data"]) == 1
    assert length(hd(data["data"])["messages"]) == 2
    assert Threads.list(template, %{}) == []
    {:ok, staff_token, _} = Feedback.start_review(template, keys.review, "Staff")

    assert visitor()
           |> put_req_header("authorization", "Bearer " <> staff_token)
           |> get("/api/projects/#{thread["project_id"]}/comments")
           |> json_response(401)

    assert visitor()
           |> post("/api/projects/#{template.id}/comments", attrs())
           |> json_response(401)
  end

  test "signup upgrades the identity and revokes its anonymous session; login restores feedback" do
    first = visitor() |> post("/demo/comments", attrs())
    thread = json_response(first, 201)["data"]
    old_token = get_session(first, :account_token)
    old_account = Accounts.current(old_token)
    signed_up = first |> next() |> post("/signup", signup_attrs())
    assert redirected_to(signed_up) == "/app"
    account = Accounts.current(get_session(signed_up, :account_token))
    assert account.id == old_account.id
    assert account.demo_project_id == old_account.demo_project_id
    assert is_nil(account.expires_at)
    assert is_nil(Accounts.current(old_token))
    assert account.password_hash != "a long demo passphrase"
    data = signed_up |> next() |> get("/demo/comments") |> json_response(200)
    assert data["registered"]
    assert hd(data["data"])["id"] == thread["id"]
    assert hd(hd(data["data"])["messages"])["author"]["kind"] == "account"
    assert signed_up |> next() |> get("/app") |> html_response(200)

    created =
      signed_up
      |> next()
      |> post("/app/projects", %{
        project: %{name: "Customer site", origin: "https://customer.test"}
      })

    assert redirected_to(created) =~ "/app/projects/"
    signed_up |> next() |> post("/app/logout")
    assert is_nil(Accounts.current(get_session(signed_up, :account_token)))
    login = visitor() |> post("/login", signup_attrs())
    assert redirected_to(login) == "/app"
    assert Accounts.current(get_session(login, :account_token)).id == account.id

    assert login
           |> next()
           |> get("/demo/comments")
           |> json_response(200)
           |> Map.get("data")
           |> hd()
           |> Map.get("id") == thread["id"]
  end

  test "anonymous sessions cannot manage workspaces or overwrite a registered identity" do
    first = visitor() |> post("/demo/comments", attrs())
    assert first |> next() |> get("/app") |> redirected_to() == "/app/login"
    signed_up = first |> next() |> post("/signup", signup_attrs())
    assert redirected_to(signed_up) == "/app"
    assert signed_up |> next() |> post("/signup", signup_attrs()) |> html_response(422)
    other = visitor() |> post("/demo/comments", attrs())
    other_account = Accounts.current(get_session(other, :account_token))
    assert other |> next() |> post("/signup", signup_attrs()) |> html_response(422)
    assert is_nil(Accounts.current(get_session(other, :account_token)).email)
    assert Repo.get!(Account, other_account.id).demo_project_id == other_account.demo_project_id

    assert visitor()
           |> post("/login", %{account: %{email: "jamie@example.com", password: "incorrect"}})
           |> html_response(401)
  end

  test "origin, CSRF, and public write limits are enforced" do
    assert visitor()
           |> put_req_header("origin", "https://evil.test")
           |> post("/demo/comments", attrs())
           |> json_response(403)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      visitor()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/demo/comments", attrs())
    end

    conn = visitor()
    for _ <- 1..30, do: assert(conn |> post("/demo/comments", %{}) |> json_response(422))
    assert conn |> post("/demo/comments", attrs()) |> json_response(429)
  end

  test "expired anonymous projects are purged, registered projects survive" do
    first = visitor() |> post("/demo/comments", attrs())
    account = Accounts.current(get_session(first, :account_token))

    second =
      visitor() |> post("/demo/comments", attrs()) |> next() |> post("/signup", signup_attrs())

    registered = Accounts.current(get_session(second, :account_token))

    Repo.update!(
      Ecto.Changeset.change(account, expires_at: DateTime.add(DateTime.utc_now(), -1, :day))
    )

    assert is_nil(Accounts.current(get_session(first, :account_token)))
    assert {:ok, 1} = Accounts.prune_expired()
    assert is_nil(Repo.get(Account, account.id))
    assert is_nil(Feedback.project(account.demo_project_id))
    assert Feedback.project(registered.demo_project_id)
    assert Repo.get(Account, registered.id)
  end

  test "weak passwords create nothing and new logins revoke the previous session" do
    attrs = put_in(signup_attrs(), ["account", "password"], "short")
    assert visitor() |> post("/signup", attrs) |> html_response(422)
    assert Repo.aggregate(Account, :count) == 0
    signup = visitor() |> post("/signup", signup_attrs())
    original_token = get_session(signup, :account_token)
    login = visitor() |> post("/login", signup_attrs())
    assert redirected_to(login) == "/app"
    assert is_nil(Accounts.current(original_token))
    assert Accounts.current(get_session(login, :account_token))
  end

  test "signup without a demo works and disabled demo creates nothing" do
    conn = visitor() |> post("/signup", signup_attrs())
    assert redirected_to(conn) == "/app"
    assert is_nil(Accounts.current(get_session(conn, :account_token)).demo_project_id)
    Application.delete_env(:fluently, :dogfood_project_id)
    assert visitor() |> post("/demo/comments", attrs()) |> json_response(404)
  end

  test "private-demo deletion preserves visitor isolation and works after signup" do
    owner = visitor() |> post("/demo/comments", attrs())
    thread = json_response(owner, 201)["data"]
    message = hd(thread["messages"])
    assert message["can_delete"]
    path = "/demo/comments/#{thread["id"]}/messages/#{message["id"]}"
    other = visitor() |> post("/demo/comments", attrs())
    assert other |> next() |> delete(path) |> json_response(404)
    assert visitor() |> delete(path) |> json_response(404)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      owner |> next() |> put_private(:plug_skip_csrf_protection, false) |> delete(path)
    end

    replied =
      owner
      |> next()
      |> post("/demo/comments/#{thread["id"]}/replies", %{body: "Remove this reply"})

    reply = json_response(replied, 200)["data"]["messages"] |> List.last()

    result =
      owner
      |> next()
      |> delete("/demo/comments/#{thread["id"]}/messages/#{reply["id"]}")
      |> json_response(200)

    refute result["deleted_thread"]
    assert length(result["data"]["messages"]) == 1
    saved = owner |> next() |> post("/signup", signup_attrs())
    assert saved |> next() |> delete(path) |> json_response(200) |> Map.fetch!("deleted_thread")

    assert saved |> next() |> get("/demo/comments") |> json_response(200) |> Map.fetch!("data") ==
             []

    assert other
           |> next()
           |> get("/demo/comments")
           |> json_response(200)
           |> Map.fetch!("data")
           |> length() == 1
  end
end
