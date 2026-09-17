defmodule FluentlyWeb.HealthController do
  use FluentlyWeb, :controller

  def show(conn, _params) do
    case Fluently.Repo.query("SELECT 1", [], timeout: 2_000) do
      {:ok, _} -> text(conn, "ok")
      {:error, _} -> conn |> put_status(:service_unavailable) |> text("unavailable")
    end
  end
end
