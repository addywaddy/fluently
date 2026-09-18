defmodule FluentlyWeb.ClientIP do
  @moduledoc "Trust the nearest client IP only from the configured single ingress proxy."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    trusted = Keyword.get(opts, :trusted, Application.get_env(:fluently, :trusted_proxy_ips, []))

    if conn.remote_ip in trusted do
      # Kamal appends its actual TCP peer after any caller-supplied values.
      # Never walk past that peer: additional upstream proxies are not trusted.
      value = get_req_header(conn, "x-forwarded-for") |> List.last()

      case client_ip(value) do
        {:ok, ip} -> %{conn | remote_ip: ip}
        _ -> conn
      end
    else
      conn
    end
  end

  defp client_ip(value) when is_binary(value) and byte_size(value) <= 4096 do
    value
    |> String.split(",")
    |> List.last()
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_strict_address()
  end

  defp client_ip(_), do: :error
end
