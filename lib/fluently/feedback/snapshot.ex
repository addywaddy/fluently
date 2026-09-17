defmodule Fluently.Feedback.Snapshot do
  use Ecto.Schema
  @primary_key {:thread_id, :binary_id, autogenerate: false}
  schema "feedback_snapshots" do
    field :image, :binary
    field :width, :integer
    field :height, :integer
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
