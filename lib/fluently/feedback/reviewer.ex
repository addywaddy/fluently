defmodule Fluently.Feedback.Reviewer do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "reviewers" do
    field :project_id, Ecto.UUID
    field :name, :string
    field :kind, :string, default: "guest"
    field :external_id, :string
    timestamps(type: :utc_datetime_usec)
  end
end
