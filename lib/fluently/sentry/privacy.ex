defmodule Fluently.Sentry.Privacy do
  @moduledoc "Minimizes automatically collected error-report context."

  def url(conn), do: clean_url(Plug.Conn.request_url(conn))

  # PlugCapture uses this for connection arguments in Phoenix.ActionClauseError.
  def scrub_conn(conn) do
    %{
      conn
      | params: %{},
        body_params: %{},
        query_params: %{},
        query_string: "",
        req_headers: [],
        cookies: %{},
        req_cookies: %{},
        resp_cookies: %{},
        assigns: %{},
        private: %{},
        remote_ip: {0, 0, 0, 0}
    }
  end

  def before_send(event) do
    request =
      if event.request do
        %Sentry.Interfaces.Request{
          method: event.request.method,
          url: clean_url(event.request.url)
        }
      end

    %{event | request: request, user: %{}, extra: %{}, breadcrumbs: [], attachments: []}
  end

  defp clean_url(nil), do: nil

  defp clean_url(url) do
    uri = URI.parse(url)
    URI.to_string(%{uri | query: nil, fragment: nil, userinfo: nil})
  end
end
