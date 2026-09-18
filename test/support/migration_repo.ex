defmodule Fluently.MigrationRepo do
  use Ecto.Repo, otp_app: :fluently, adapter: Ecto.Adapters.SQLite3
end
