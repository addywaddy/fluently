defmodule Fluently.Repo do
  use Ecto.Repo,
    otp_app: :fluently,
    adapter: Ecto.Adapters.Postgres
end
