defmodule Fluently.SentryTest do
  use FluentlyWeb.ConnCase, async: false
  import Sentry.Test

  setup :start_collecting_sentry_reports

  test "request reports omit customer context but keep the exception and stack", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer private-token")
      |> put_req_header("cookie", "session=private-cookie")
      |> get("/up?token=private-query")

    assert response(conn, 200) == "ok"
    Sentry.Context.set_user_context(%{email: "private@example.test"})
    Sentry.Context.set_extra_context(%{body: "private comment", password: "private-password"})

    try do
      Enum.fetch!([], 0)
    rescue
      exception -> Sentry.capture_exception(exception, stacktrace: __STACKTRACE__)
    end

    assert [event] = pop_sentry_reports()
    assert event.request.method == "GET"
    assert event.request.url == "http://www.example.com/up"
    assert event.request.query_string == nil
    assert event.request.headers == nil
    assert event.request.cookies == nil
    assert event.request.data == nil
    assert event.request.env == nil
    assert event.user == %{}
    assert event.extra == %{}
    assert event.breadcrumbs == []
    assert [exception] = event.exception
    assert exception.type == "Enum.OutOfBoundsError"
    assert exception.stacktrace.frames != []
  end

  test "PlugCapture reports an unhandled Plug exception" do
    assert_raise RuntimeError, "Synthetic Plug capture test", fn ->
      Fluently.SentryCrashPlug.call(Plug.Test.conn(:get, "/crash"), [])
    end

    assert [event] = pop_sentry_reports()
    assert event.source == :plug
    assert hd(event.exception).value == "Synthetic Plug capture test"
    assert hd(event.exception).stacktrace.frames != []
  end

  test "connection arguments are scrubbed before formatting action-clause exceptions" do
    conn =
      Plug.Test.conn(:post, "/signup?token=private-query", %{"password" => "private-password"})
      |> Plug.Conn.assign(:account, %{email: "private@example.test"})
      |> Plug.Conn.put_private(:session, "private-session")
      |> Plug.Conn.put_req_header("authorization", "Bearer private-token")
      |> Fluently.Sentry.Privacy.scrub_conn()

    refute inspect(conn) =~ "private-"
    assert conn.assigns == %{}
    assert conn.private == %{}
    assert conn.query_string == ""
    assert conn.remote_ip == {0, 0, 0, 0}
  end
end
