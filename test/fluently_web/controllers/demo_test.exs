defmodule FluentlyWeb.DemoTest do
  use FluentlyWeb.ConnCase, async: false
  alias Fluently.{Accounts, Feedback, GuestReviews, Repo, Threads}
  alias Fluently.Accounts.{Account, User}
  alias Fluently.Feedback.{GuestReviewSession, Workspace}
  import Fluently.FeedbackFixtures

  setup do
    {:ok, w, _} = Feedback.create_workspace("Fluently")
    {:ok, p, _} = Feedback.create_project(w, %{name: "Fluently", origin: "http://localhost"})
    p = Repo.update!(Ecto.Changeset.change(p, public_feedback: true))
    previous = Application.get_env(:fluently, :feedback_project_id)
    Application.put_env(:fluently, :feedback_project_id, p.id)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:fluently, :feedback_project_id, previous),
        else: Application.delete_env(:fluently, :feedback_project_id)
    end)

    %{project: p, workspace: w}
  end

  defp visitor do
    n = System.unique_integer([:positive])

    %{build_conn() | host: "localhost", remote_ip: {10, 21, rem(div(n, 256), 256), rem(n, 256)}}
    |> put_req_header("content-type", "application/json")
  end

  defp next(conn), do: conn |> recycle() |> put_req_header("content-type", "application/json")

  defp signup_attrs,
    do: %{
      account: %{name: "Jamie", email: "jamie@example.com", password: "a long demo passphrase"}
    }

  test "only successful first comment creates a guest user and session; never an account or workspace",
       %{project: p} do
    baseline_users = Repo.aggregate(User, :count)
    assert visitor() |> get("/demo/comments") |> json_response(200) |> Map.fetch!("data") == []
    assert visitor() |> post("/demo/comments", %{}) |> json_response(422)
    assert Repo.aggregate(User, :count) == baseline_users
    assert Repo.aggregate(GuestReviewSession, :count) == 0
    first = visitor() |> post("/demo/comments", attrs())
    thread = json_response(first, 201)["data"]
    assert thread["project_id"] == p.id
    assert Repo.aggregate(User, :count) == baseline_users + 1
    assert Repo.aggregate(GuestReviewSession, :count) == 1
    assert Repo.aggregate(Account, :count) == 0
    assert Repo.aggregate(Workspace, :count) == 1
    assert is_nil(get_session(first, :account_token))
    assert first.resp_cookies["_fluently_key"].http_only
    second = first |> next() |> post("/demo/comments", attrs()) |> json_response(201)

    assert hd(second["data"]["messages"])["author"]["id"] ==
             hd(thread["messages"])["author"]["id"]

    assert Repo.aggregate(User, :count) == baseline_users + 1
  end

  test "signup preserves browser guest session without claiming it; another device cannot recover guest feedback",
       %{project: p} do
    first = visitor() |> post("/demo/comments", attrs())
    token = get_session(first, :guest_review_token)
    guest = GuestReviews.current(p, token)
    signed = first |> next() |> post("/signup", signup_attrs())
    assert redirected_to(signed) == "/app"
    account = Accounts.current(get_session(signed, :account_token))
    refute account.user_id == guest.user_id
    assert is_nil(account.feedback_reviewer_id)
    assert is_nil(account.demo_project_id)
    assert get_session(signed, :guest_review_token) == token
    assert GuestReviews.current(p, token).kind == "anonymous"

    assert signed
           |> next()
           |> get("/demo/comments")
           |> json_response(200)
           |> Map.fetch!("data")
           |> length() == 1

    login = visitor() |> post("/login", signup_attrs())
    assert redirected_to(login) == "/app"

    assert login |> next() |> get("/demo/comments") |> json_response(200) |> Map.fetch!("data") ==
             []

    added = login |> next() |> post("/demo/comments", attrs()) |> json_response(201)
    assert hd(added["data"]["messages"])["author"]["name"] == "Guest"
    assert hd(added["data"]["messages"])["author"]["kind"] == "account"
    listed = login |> next() |> get("/demo/comments") |> json_response(200)
    assert listed["identity"] == %{"kind" => "guest", "name" => "Guest"}
  end

  test "registered owner authors with account identity; nonmember stays unlinked", %{
    project: p,
    workspace: w
  } do
    {:ok, {owner, token}} = Accounts.register(nil, signup_attrs().account)
    owner = Repo.update!(Ecto.Changeset.change(owner, workspace_id: w.id))
    conn = visitor() |> init_test_session(account_token: token) |> post("/demo/comments", attrs())
    thread = json_response(conn, 201)["data"]
    identity = Repo.get!(Fluently.Feedback.ProjectUser, hd(thread["messages"])["author"]["id"])
    assert identity.user_id == owner.user_id
    assert identity.project_id == p.id
    assert identity.kind == "account"
    assert Repo.aggregate(GuestReviewSession, :count) == 0
    listed = conn |> next() |> get("/demo/comments") |> json_response(200)
    assert listed["identity"] == %{"kind" => "account", "name" => owner.name}
  end

  test "granting and revoking membership never relinks earlier guest authorship", %{
    project: p,
    workspace: w
  } do
    first = visitor() |> post("/demo/comments", attrs())
    thread_id = json_response(first, 201)["data"]["id"]
    guest = GuestReviews.current(p, get_session(first, :guest_review_token))
    signed = first |> next() |> post("/signup", signup_attrs())
    account = Accounts.current(get_session(signed, :account_token))
    {:ok, membership} = Fluently.ProjectAccess.grant(w, p.id, account.email)
    member = signed |> next() |> post("/demo/comments", attrs())
    member_author = hd(json_response(member, 201)["data"]["messages"])["author"]["id"]
    assert Repo.get!(Fluently.Feedback.ProjectUser, member_author).user_id == account.user_id
    assert Threads.get(p, thread_id).reviewer_id == guest.id
    assert Repo.get!(Fluently.Feedback.ProjectUser, guest.id).user_id == guest.user_id
    refute guest.user_id == account.user_id
    assert :ok = Fluently.ProjectAccess.revoke(w, p.id, membership.id)
    visible = member |> next() |> get("/demo/comments") |> json_response(200)
    assert Enum.map(visible["data"], & &1["id"]) == [thread_id]
    later = member |> next() |> post("/demo/comments", attrs()) |> json_response(201)
    assert hd(later["data"]["messages"])["author"]["id"] == guest.id
  end

  test "legacy session capability can transition without linking or updating a registered account",
       %{project: p} do
    {:ok, identity} = Feedback.create_project_user(p, %{name: "Legacy guest"})
    {:ok, thread} = Threads.create(p, identity, Map.put(attrs(), "page", p.origin <> "/"))
    old = Feedback.secret()

    Repo.insert!(%GuestReviewSession{
      project_user_id: identity.id,
      token_hash: Feedback.hash(old),
      expires_at: DateTime.add(DateTime.utc_now(), 1, :day)
    })

    conn = visitor() |> init_test_session(account_token: old) |> get("/demo/comments")
    assert hd(json_response(conn, 200)["data"])["id"] == thread.id
    assert get_session(conn, :guest_review_token) == old
    signed = conn |> next() |> post("/signup", signup_attrs())
    assert redirected_to(signed) == "/app"
    refute Accounts.current(get_session(signed, :account_token)).user_id == identity.user_id
    assert Repo.get!(Fluently.Feedback.ProjectUser, identity.id).name == "Legacy guest"
  end

  test "rolling-release anonymous cookies migrate, but registered login cannot recover guest identity",
       %{project: p} do
    {:ok, w, _} = Feedback.create_workspace("Legacy")

    identity =
      Repo.insert!(%Fluently.Feedback.ProjectUser{
        project_id: p.id,
        name: "Old guest",
        kind: "anonymous"
      })

    old = Feedback.secret()

    account =
      Repo.insert!(%Account{
        workspace_id: w.id,
        feedback_reviewer_id: identity.id,
        session_hash: Feedback.hash(old),
        session_expires_at: DateTime.add(DateTime.utc_now(), 2, :day),
        expires_at: DateTime.add(DateTime.utc_now(), 1, :day)
      })

    assert GuestReviews.current(p, old).id == identity.id
    assert Repo.get!(Fluently.Feedback.ProjectUser, identity.id).user_id == identity.id
    assert Repo.get!(User, identity.id).kind == "guest"
    assert Repo.aggregate(GuestReviewSession, :count) == 1

    {:ok, other, _} = Feedback.create_project(w, %{name: "Other", origin: "http://localhost"})
    refute GuestReviews.current(other, old)
    new_token = Feedback.secret()

    Repo.update!(
      Ecto.Changeset.change(account,
        email: "old@example.com",
        expires_at: nil,
        session_hash: Feedback.hash(new_token)
      )
    )

    registered = Accounts.current(new_token)
    assert registered.user_id == account.id
    assert Repo.get!(User, registered.user_id).kind == "registered"
    refute GuestReviews.current(p, new_token)
    assert GuestReviews.current(p, old).id == identity.id
  end

  test "origin, CSRF, and public write limits remain enforced" do
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

  test "signup and password login preserve session revocation and reject weak credentials" do
    assert visitor()
           |> post("/signup", put_in(signup_attrs(), [:account, :password], "short"))
           |> html_response(422)

    assert Repo.aggregate(Account, :count) == 0
    signup = visitor() |> post("/signup", signup_attrs())
    token = get_session(signup, :account_token)
    assert signup |> next() |> post("/signup", signup_attrs()) |> html_response(422)

    assert visitor()
           |> post("/login", put_in(signup_attrs(), [:account, :password], "incorrect"))
           |> html_response(401)

    login = visitor() |> post("/login", signup_attrs())
    assert redirected_to(login) == "/app"
    assert Accounts.current(token)
    login |> next() |> post("/app/logout")
    assert is_nil(Accounts.current(get_session(login, :account_token)))
  end

  test "snapshots and guest access survive reload but not session expiry", %{project: p} do
    first = visitor() |> post("/demo/comments", attrs())
    thread = json_response(first, 201)["data"]
    path = "/demo/comments/#{thread["id"]}/snapshot"
    assert first |> next() |> post(path, %{data_url: snapshot()}) |> json_response(200)
    assert first |> next() |> get(path) |> json_response(200)
    token = get_session(first, :guest_review_token)
    session = Repo.get_by!(GuestReviewSession, token_hash: Feedback.hash(token))

    Repo.update!(
      Ecto.Changeset.change(session, expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    )

    assert first |> next() |> get(path) |> json_response(404)
    assert Threads.get(p, thread["id"])
    assert Fluently.Snapshots.get(p, thread["id"])
  end

  test "same-origin aliases still canonicalize storage to the shared project", %{project: p} do
    conn = %{visitor() | host: "127.0.0.1", port: 4000}

    saved =
      conn |> put_req_header("origin", "http://127.0.0.1:4000") |> post("/demo/comments", attrs())

    thread = json_response(saved, 201)["data"]
    assert thread["page"] == "http://127.0.0.1:4000/"
    assert Threads.get(p, thread["id"]).page == p.origin <> "/"
  end
end
