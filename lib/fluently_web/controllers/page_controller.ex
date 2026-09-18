defmodule FluentlyWeb.PageController do
  use FluentlyWeb, :controller

  def home(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> render(:home,
      feedback_demo: Fluently.Accounts.demo_enabled?(),
      navigation_identity: navigation_identity(conn)
    )
  end

  defp navigation_identity(conn) do
    case Fluently.Accounts.current(get_session(conn, :account_token)) do
      %{email: email, name: name} when is_binary(email) -> %{name: name, detail: email}
      _ -> pilot_identity(conn)
    end
  end

  defp pilot_identity(conn) do
    with {:ok, id} <-
           Phoenix.Token.verify(FluentlyWeb.Endpoint, "owner-v1", get_session(conn, :owner) || "",
             max_age: 43_200
           ),
         workspace when not is_nil(workspace) <- Fluently.Feedback.workspace(id) do
      %{name: workspace.name, detail: "Workspace owner"}
    else
      _ -> nil
    end
  end
end
