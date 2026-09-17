defmodule FluentlyWeb.PageControllerTest do
  use FluentlyWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert conn
           |> html_response(200)
           |> LazyHTML.from_document()
           |> LazyHTML.query("main#welcome")
           |> Enum.any?()
  end
end
