defmodule FluentlyWeb.ErrorJSONTest do
  use FluentlyWeb.ConnCase, async: false

  test "renders 404" do
    assert FluentlyWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert FluentlyWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
