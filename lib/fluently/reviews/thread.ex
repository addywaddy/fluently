defmodule Fluently.Reviews.Thread do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "feedback_threads" do
    field :project_id, Ecto.UUID
    belongs_to :author, Fluently.Accounts.User, foreign_key: :author_user_id, type: Ecto.UUID
    belongs_to :reviewer, Fluently.Projects.ProjectUser, type: Ecto.UUID
    field :page, :string
    field :status, :string, default: "open"
    field :anchor, :map
    field :context, :map
    has_one :snapshot, Fluently.Reviews.Snapshot
    has_many :messages, Fluently.Reviews.Message
    timestamps(type: :utc_datetime_usec)
  end
end
