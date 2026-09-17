defmodule FluentlyWeb.PageController do
  use FluentlyWeb, :controller

  def home(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> render(:home, feedback_project: Application.get_env(:fluently, :dogfood_project_id))
  end
end
