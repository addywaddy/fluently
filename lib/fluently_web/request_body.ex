defmodule FluentlyWeb.RequestBody do
  @moduledoc false
  def read_body(conn, opts) do
    limit =
      case {conn.method, conn.path_info} do
        {"POST", ["demo", "comments", _, "snapshot"]} -> 307_200
        {"POST", ["api", "projects", _, "comments", _, "snapshot"]} -> 307_200
        _ -> 32_768
      end

    Plug.Conn.read_body(conn, Keyword.put(opts, :length, limit))
  end
end
