defmodule FluentlyWeb.ManageControllerTest do
  use FluentlyWeb.ConnCase, async: true
  alias Fluently.Feedback

  test "owner login, project creation and one-time keys render", %{conn: conn} do
    {:ok, workspace, key} = Feedback.create_workspace("Studio")
    html = conn |> get("/app/login") |> html_response(200) |> LazyHTML.from_document()
    assert Enum.any?(LazyHTML.query(html, "#owner-login input[type=password]"))
    conn = build_conn() |> post("/app/login", %{key: key})
    assert redirected_to(conn) == "/app"
    conn = recycle(conn) |> get("/app")
    assert html_response(conn, 200)

    conn =
      recycle(conn)
      |> post("/app/projects", %{project: %{name: "Checkout", origin: "https://example.com"}})

    conn = recycle(conn) |> get(redirected_to(conn))
    doc = conn |> html_response(200) |> LazyHTML.from_document()
    assert Enum.any?(LazyHTML.query(doc, "#delete-project input"))
    assert Enum.any?(LazyHTML.query(doc, "a[target=_blank]"))
    [p] = Feedback.projects(workspace)
    conn = recycle(conn) |> get("/app/projects/#{p.id}")
    doc = conn |> html_response(200) |> LazyHTML.from_document()
    refute Enum.any?(LazyHTML.query(doc, "a[target=_blank]"))
    assert length(Feedback.projects(workspace)) == 1
  end

  test "owner screens require login and enforce workspace scope", %{conn: conn} do
    assert conn |> get("/app") |> redirected_to() == "/app/login"
    {:ok, workspace, _} = Feedback.create_workspace("First")

    {:ok, p, _} =
      Feedback.create_project(workspace, %{"name" => "Private", "origin" => "https://example.com"})

    {:ok, _, key} = Feedback.create_workspace("Second")
    conn = build_conn() |> post("/app/login", %{key: key})
    assert conn |> recycle() |> get("/app/projects/#{p.id}") |> response(404)
    assert conn |> recycle() |> post("/app/projects/#{p.id}/rotate") |> response(404)

    assert conn
           |> recycle()
           |> post("/app/projects/#{p.id}/delete", %{confirm: "delete"})
           |> response(404)
  end
end
