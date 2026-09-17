defmodule Fluently.SentryCrashPlug do
  @moduledoc false
  use Plug.Builder
  use Sentry.PlugCapture

  plug Sentry.PlugContext, body_scrubber: nil
  plug :crash

  defp crash(_conn, _opts), do: raise("Synthetic Plug capture test")
end
