defmodule Fluently.Accounts.Retention do
  @moduledoc "Hourly removal of expired, unclaimed demo workspaces."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def init(_),
    do:
      (
        schedule()
        {:ok, nil}
      )

  def handle_info(:prune, state) do
    Fluently.Accounts.prune_expired()
    Fluently.GuestReviews.prune_expired()
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :prune, :timer.hours(1))
end
