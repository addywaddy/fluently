defmodule Fluently.Projects.Workspace do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "workspaces" do
    field :name, :string
    field :access_hash, :binary
    timestamps(type: :utc_datetime_usec)
  end
end
