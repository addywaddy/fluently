defmodule FluentlyWeb.DogfoodTest do
  use FluentlyWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:fluently, :demo_enabled)
    on_exit(fn -> Application.put_env(:fluently, :demo_enabled, previous) end)
    :ok
  end

  test "the landing embed needs no project ID" do
    Application.put_env(:fluently, :demo_enabled, true)
    document = build_conn() |> get("/") |> html_response(200) |> LazyHTML.from_document()

    assert Enum.any?(
             LazyHTML.query(
               document,
               "script#fluently-embed:not([data-project])[data-demo='true'][src='/embed.js']"
             )
           )

    assert Enum.any?(LazyHTML.query(document, "[data-feedback-id='landing-hero-title']"))
    login = build_conn() |> get("/app/login") |> html_response(200) |> LazyHTML.from_document()
    refute Enum.any?(LazyHTML.query(login, "script#fluently-embed"))
  end

  test "landing demo can be disabled" do
    Application.put_env(:fluently, :demo_enabled, false)
    document = build_conn() |> get("/") |> html_response(200) |> LazyHTML.from_document()
    refute Enum.any?(LazyHTML.query(document, "script#fluently-embed"))
  end
end
