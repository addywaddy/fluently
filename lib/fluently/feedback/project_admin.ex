defmodule Fluently.Feedback.ProjectAdmin do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "project_admins" do
    field :project_id, Ecto.UUID
    field :workspace_id, Ecto.UUID
    field :reviewer_id, Ecto.UUID
  end
end
