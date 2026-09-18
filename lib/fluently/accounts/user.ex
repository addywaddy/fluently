defmodule Fluently.Accounts.User do
  @moduledoc "A person identity. Guest users have no account, credentials or workspace."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :kind, :string, default: "guest"
    timestamps(type: :utc_datetime_usec)
  end
end
