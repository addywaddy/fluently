defmodule FluentlyWeb.HealthControllerTest do
  use FluentlyWeb.ConnCase, async: false

  test "deployment readiness is public and does not create a session", %{conn: conn} do
    conn = get(conn, "/up")
    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "set-cookie") == []
  end
end
