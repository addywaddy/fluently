defmodule Fluently.RateLimit do
  @moduledoc "Bounded, single-instance fixed-window limiter. Keys contain no raw credentials."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def allow?(key, limit), do: GenServer.call(__MODULE__, {:allow, key, limit})
  def init(_), do: {:ok, %{}}

  def handle_call({:allow, key, limit}, _from, state) do
    now = System.monotonic_time(:second)
    state = Map.reject(state, fn {_, {expiry, _}} -> expiry <= now end)
    {expiry, count} = Map.get(state, key, {now + 60, 0})

    if count < limit and (map_size(state) < 20_000 or Map.has_key?(state, key)) do
      {:reply, true, Map.put(state, key, {expiry, count + 1})}
    else
      {:reply, false, state}
    end
  end
end
