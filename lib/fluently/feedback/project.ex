defmodule Fluently.Feedback.Project do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "projects" do
    field :workspace_id, Ecto.UUID
    field :public_feedback, :boolean, default: false
    field :name, :string
    field :origin, :string
    field :review_hash, :binary
    field :api_hash, :binary
    field :review_expires_at, :utc_datetime_usec
    field :credential_version, :integer, default: 1
    has_many :memberships, Fluently.Feedback.ProjectMembership
    timestamps(type: :utc_datetime_usec)
  end
end
