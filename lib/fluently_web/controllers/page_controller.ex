defmodule FluentlyWeb.PageController do
  use FluentlyWeb, :controller

  def home(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> render(:home, feedback_demo: Fluently.Accounts.demo_enabled?())
  end
end
