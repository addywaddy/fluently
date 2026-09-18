defmodule Fluently.Feedback.ProjectUser do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  # Retain the physical table and foreign-key names for release compatibility.
  schema "reviewers" do
    field :account_member, :boolean, virtual: true, default: false
    field :user_id, Ecto.UUID
    field :project_id, Ecto.UUID
    field :name, :string
    field :kind, :string, default: "guest"
    field :external_id, :string
    timestamps(type: :utc_datetime_usec)
  end
end
