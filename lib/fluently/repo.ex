defmodule Fluently.Repo do
  use Ecto.Repo,
    otp_app: :fluently,
    adapter: Ecto.Adapters.SQLite3
end
