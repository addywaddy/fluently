defmodule Fluently.Feedback.ProjectMembership do
  @moduledoc "Explicit project access for ordinary account members."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "project_memberships" do
    field :project_id, Ecto.UUID
    field :user_id, Ecto.UUID
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:project_id, :user_id])
    |> validate_required([:project_id, :user_id])
    |> unique_constraint([:project_id, :user_id])
  end
end
