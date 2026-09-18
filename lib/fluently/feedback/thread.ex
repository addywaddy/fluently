defmodule Fluently.Feedback.Thread do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "feedback_threads" do
    field :project_id, Ecto.UUID
    belongs_to :reviewer, Fluently.Feedback.ProjectUser, type: Ecto.UUID
    field :page, :string
    field :status, :string, default: "open"
    field :anchor, :map
    field :context, :map
    has_one :snapshot, Fluently.Feedback.Snapshot
    has_many :messages, Fluently.Feedback.Message
    timestamps(type: :utc_datetime_usec)
  end
end
