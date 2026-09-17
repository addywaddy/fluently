defmodule FluentlyWeb.DogfoodTest do
  use FluentlyWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:fluently, :dogfood_project_id)
    on_exit(fn -> Application.put_env(:fluently, :dogfood_project_id, previous) end)
    :ok
  end

  test "the configured landing embed contains only the public project ID" do
    id = Ecto.UUID.generate()
    Application.put_env(:fluently, :dogfood_project_id, id)
    document = build_conn() |> get("/") |> html_response(200) |> LazyHTML.from_document()

    assert Enum.any?(
             LazyHTML.query(
               document,
               "script#fluently-embed[data-project='#{id}'][src='/embed.js']"
             )
           )

    assert Enum.any?(LazyHTML.query(document, "[data-feedback-id='landing-hero-title']"))
    login = build_conn() |> get("/app/login") |> html_response(200) |> LazyHTML.from_document()
    refute Enum.any?(LazyHTML.query(login, "script#fluently-embed"))
  end

  test "self-installation is opt-in" do
    Application.delete_env(:fluently, :dogfood_project_id)
    document = build_conn() |> get("/") |> html_response(200) |> LazyHTML.from_document()
    refute Enum.any?(LazyHTML.query(document, "script#fluently-embed"))
  end
end
