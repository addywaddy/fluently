defmodule FluentlyWeb.PageControllerTest do
  use FluentlyWeb.ConnCase
  alias Fluently.{Accounts, Feedback, Repo}

  defp document(conn), do: conn |> html_response(200) |> LazyHTML.from_document()
  defp present?(doc, selector), do: Enum.any?(LazyHTML.query(doc, selector))

  test "landing visitors see login and signup", %{conn: conn} do
    doc = conn |> get(~p"/") |> document()
    assert present?(doc, "main#welcome")
    assert present?(doc, "#landing-login")
    assert present?(doc, "#landing-signup")
    refute present?(doc, "#landing-account")
  end

  test "signed-in account gets an accessible avatar and CSRF-protected logout" do
    {:ok, {account, token}} =
      Accounts.register(nil, %{
        name: "Jane Smith",
        email: "jane@example.test",
        password: "a long enough test password"
      })

    conn = build_conn() |> init_test_session(account_token: token) |> get("/")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    doc = document(conn)

    assert present?(
             doc,
             ~s(#landing-account[data-feedback-exclude] summary[aria-label="Account menu for Jane Smith"])
           )

    assert LazyHTML.text(LazyHTML.query(doc, "#landing-account summary")) =~ "JS"
    assert present?(doc, ~s(#landing-projects[href="/app"]))

    assert present?(
             doc,
             ~s(#landing-logout[method="post"][action="/app/logout"] input[name="_csrf_token"])
           )

    refute present?(doc, "#landing-login")
    refute present?(doc, "#landing-signup")

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn |> recycle() |> put_private(:plug_skip_csrf_protection, false) |> post("/app/logout")
    end

    logged_out = conn |> recycle() |> post("/app/logout")
    assert redirected_to(logged_out) == "/"
    refute Accounts.current(token)
    assert Repo.get!(Fluently.Accounts.Account, account.id).session_hash == nil
    assert logged_out |> recycle() |> get("/") |> document() |> present?("#landing-login")
  end

  test "expired and guest sessions are not shown as registered accounts" do
    {:ok, {account, token}} =
      Accounts.register(nil, %{
        name: "Expired",
        email: "expired@example.test",
        password: "a long enough test password"
      })

    Repo.update!(
      Ecto.Changeset.change(account,
        session_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      )
    )

    for session <- [
          %{account_token: token},
          %{guest_review_token: Feedback.secret()},
          %{account_token: Feedback.secret()}
        ] do
      doc = build_conn() |> init_test_session(session) |> get("/") |> document()
      assert present?(doc, "#landing-login")
      refute present?(doc, "#landing-account")
    end
  end

  test "pilot workspace owners also have an account menu" do
    {:ok, _, key} = Feedback.create_workspace("Pilot studio")
    login = build_conn() |> post("/app/login", %{key: key})
    doc = login |> recycle() |> get("/") |> document()
    assert present?(doc, "#landing-account")
    refute present?(doc, "#landing-login")
  end
end
