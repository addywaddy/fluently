defmodule FluentlyWeb.PageController do
  use FluentlyWeb, :controller

  def home(conn, _params) do
    render(conn, :home, feedback_project: Application.get_env(:fluently, :dogfood_project_id))
  end
end
