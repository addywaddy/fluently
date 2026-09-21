defmodule FluentlyWeb.ReviewConnectTest do
  use FluentlyWeb.ConnCase, async: false
  alias Fluently.{Accounts, AccountReviews, Feedback, ProjectAccess, Repo}
  alias Fluently.Accounts.AccountMembership
  alias Fluently.Accounts.ReviewGrant
  import Fluently.FeedbackFixtures

  setup do
    {:ok, {account, login}} =
      Accounts.register(nil, %{
        name: "Owner",
        email: "owner@example.test",
        password: "long enough password for tests"
      })

    workspace = Feedback.workspace(account.workspace_id)

    {:ok, project, keys} =
      Feedback.create_project(workspace, %{name: "Customer", origin: "https://customer.test"})

    %{account: account, login: login, project: project, keys: keys, workspace: workspace}
  end

  defp pending(project) do
    verifier = Feedback.secret()

    {%{
       "project" => project.id,
       "return_to" => project.origin <> "/checkout?tab=cart#section=price",
       "state" => Feedback.secret(),
       "challenge" => Base.url_encode64(Feedback.hash(verifier), padding: false)
     }, verifier}
  end

  defp api(project, token \\ nil) do
    conn = build_conn() |> put_req_header("origin", project.origin)
    if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn
  end

  defp grant(project, account) do
    {params, verifier} = pending(project)
    {:ok, code} = AccountReviews.issue(project, account, params["challenge"])
    {:ok, result} = AccountReviews.exchange(project, code, verifier)
    result.token
  end

  test "explicit login round trip preserves state, creates account authorship and returns no account ID or email",
       c do
    {params, verifier} = pending(c.project)
    start = build_conn() |> get("/review/connect", params)
    assert redirected_to(start) == "/login"

    signed =
      start
      |> recycle()
      |> post("/login", %{
        account: %{email: c.account.email, password: "long enough password for tests"}
      })

    assert redirected_to(signed) == "/review/connect"
    confirm = signed |> recycle() |> get("/review/connect")
    assert html_response(confirm, 200) =~ "Continue as Owner"

    returned =
      confirm
      |> recycle()
      |> post("/review/connect", %{state: params["state"], action: "connect"})

    uri = returned |> redirected_to() |> URI.parse()
    assert URI.to_string(%{uri | fragment: nil}) == c.project.origin <> "/checkout?tab=cart"
    fragment = URI.decode_query(uri.fragment)
    assert fragment["fluently_state"] == params["state"]
    assert fragment["section"] == "price"
    assert is_nil(get_session(returned, :review_connect))

    exchanged =
      api(c.project)
      |> post("/api/projects/#{c.project.id}/account-sessions", %{
        code: fragment["fluently_code"],
        verifier: verifier
      })
      |> json_response(200)

    refute Jason.encode!(exchanged) =~ c.account.email
    refute Jason.encode!(exchanged) =~ c.account.id
    assert exchanged["reviewer"]["kind"] == "account"
    payload = Map.put(attrs(), "page", c.project.origin <> "/checkout")

    created =
      api(c.project, exchanged["token"])
      |> post("/api/projects/#{c.project.id}/comments", payload)
      |> json_response(201)

    author = hd(created["data"]["messages"])["author"]
    assert author["name"] == "Owner"
    assert Repo.get!(Fluently.Feedback.ProjectUser, author["id"]).user_id == c.account.user_id
    thread = Repo.get!(Fluently.Feedback.Thread, created["data"]["id"]) |> Repo.preload(:messages)
    assert thread.author_user_id == c.account.user_id
    assert hd(thread.messages).author_user_id == c.account.user_id

    list =
      api(c.project, exchanged["token"])
      |> get("/api/projects/#{c.project.id}/comments")
      |> json_response(200)

    assert list["identity"] == %{"name" => "Owner", "kind" => "account"}
  end

  test "return origin, CSRF, state, project, verifier, origin and one-use code are enforced", c do
    {params, verifier} = pending(c.project)

    for url <- [
          "https://evil.test/",
          "https://customer.test.evil.test/",
          "https://user@customer.test/",
          "javascript:alert(1)"
        ] do
      assert build_conn()
             |> get("/review/connect", Map.put(params, "return_to", url))
             |> response(400)
    end

    start =
      build_conn() |> init_test_session(account_token: c.login) |> get("/review/connect", params)

    assert start
           |> recycle()
           |> post("/review/connect", %{state: Feedback.secret(), action: "connect"})
           |> response(400)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      start
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/review/connect", %{state: params["state"], action: "connect"})
    end

    {:ok, code} = AccountReviews.issue(c.project, c.account, params["challenge"])
    assert {:error, :unauthorized} = AccountReviews.exchange(c.project, code, Feedback.secret())

    {:ok, other, _} =
      Feedback.create_project(c.workspace, %{name: "Same domain", origin: c.project.origin})

    assert {:error, :unauthorized} = AccountReviews.exchange(other, code, verifier)

    assert build_conn()
           |> post("/api/projects/#{c.project.id}/account-sessions", %{
             code: code,
             verifier: verifier
           })
           |> json_response(403)

    assert api(c.project)
           |> put_req_header("origin", "https://evil.test")
           |> post("/api/projects/#{c.project.id}/account-sessions", %{
             code: code,
             verifier: verifier
           })
           |> json_response(403)

    assert {:ok, _} = AccountReviews.exchange(c.project, code, verifier)
    assert {:error, :unauthorized} = AccountReviews.exchange(c.project, code, verifier)
  end

  test "nonmembers disclose no identity and membership never merges earlier guest authorship",
       c do
    {:ok, {outsider, token}} =
      Accounts.register(nil, %{
        name: "Private Name",
        email: "private@example.test",
        password: "another long test password"
      })

    {params, _} = pending(c.project)
    before_count = Repo.aggregate(Fluently.Feedback.ProjectUser, :count)

    start =
      build_conn() |> init_test_session(account_token: token) |> get("/review/connect", params)

    returned =
      start |> recycle() |> post("/review/connect", %{state: params["state"], action: "connect"})

    uri = URI.parse(redirected_to(returned))
    fragment = URI.decode_query(uri.fragment)
    assert fragment["fluently_result"] == "guest"
    refute fragment["fluently_code"]
    refute redirected_to(returned) =~ outsider.name
    refute redirected_to(returned) =~ outsider.email
    refute redirected_to(returned) =~ outsider.id
    assert Repo.aggregate(Fluently.Feedback.ProjectUser, :count) == before_count
    {:ok, guest_token, guest} = Feedback.start_review(c.project, c.keys.review, "Guest")
    {:ok, membership} = ProjectAccess.grant(c.workspace, c.project.id, outsider.email)
    account_token = grant(c.project, outsider)
    {:ok, member} = Feedback.authorize(c.project, account_token)
    refute member.id == guest.id
    refute member.user_id == guest.user_id
    assert {:ok, %{id: guest_id}} = Feedback.authorize(c.project, guest_token)
    assert guest_id == guest.id
    :ok = ProjectAccess.revoke(c.workspace, c.project.id, membership.id)
    assert {:error, :unauthorized} = Feedback.authorize(c.project, account_token)
    {:ok, _} = ProjectAccess.grant(c.workspace, c.project.id, outsider.email)
    assert {:error, :unauthorized} = Feedback.authorize(c.project, account_token)
  end

  test "logout, expiration, rotation and Exit revoke account review sessions", c do
    token = grant(c.project, c.account)
    assert {:ok, _} = Feedback.authorize(c.project, token)
    api(c.project, token) |> delete("/api/projects/#{c.project.id}/session") |> response(204)
    assert {:error, :unauthorized} = Feedback.authorize(c.project, token)
    token = grant(c.project, c.account)
    row = Repo.get_by!(ReviewGrant, token_hash: Feedback.hash(token))

    Repo.update!(
      Ecto.Changeset.change(row, expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    )

    assert {:error, :unauthorized} = Feedback.authorize(c.project, token)
    token = grant(c.project, c.account)
    rotated = %{c.project | credential_version: c.project.credential_version + 1}
    assert {:error, :unauthorized} = Feedback.authorize(rotated, token)
    Accounts.logout(c.account)
    assert {:error, :unauthorized} = Feedback.authorize(c.project, token)
    assert {:error, :unauthorized} = AccountReviews.issue(c.project, c.account, Feedback.secret())
    assert {:ok, _, _} = Accounts.login(c.account.email, "long enough password for tests")
    assert {:error, :unauthorized} = AccountReviews.issue(c.project, c.account, Feedback.secret())
    assert {:error, :unauthorized} = Feedback.authorize(c.project, token)
  end

  test "removing the account membership revokes an existing review grant", c do
    token = grant(c.project, c.account)

    membership =
      Repo.get_by!(AccountMembership, account_id: c.account.id, user_id: c.account.user_id)

    Repo.delete!(membership)

    assert {:error, :unauthorized} = Feedback.authorize(c.project, token)
  end

  test "expired codes fail and account members see all public project threads", c do
    {params, verifier} = pending(c.project)
    {:ok, code} = AccountReviews.issue(c.project, c.account, params["challenge"])
    row = Repo.get_by!(ReviewGrant, code_hash: Feedback.hash(code))

    Repo.update!(
      Ecto.Changeset.change(row, expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    )

    assert {:error, :unauthorized} = AccountReviews.exchange(c.project, code, verifier)
    public = Repo.update!(Ecto.Changeset.change(c.project, public_feedback: true))
    {:ok, _, guest} = Feedback.start_review(public, c.keys.review, "Guest")

    {:ok, thread} =
      Fluently.Threads.create(public, guest, Map.put(attrs(), "page", public.origin <> "/"))

    token = grant(public, c.account)
    list = api(public, token) |> get("/api/projects/#{public.id}/comments") |> json_response(200)
    assert Enum.map(list["data"], & &1["id"]) == [thread.id]
  end
end
