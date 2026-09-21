defmodule Fluently.Feedback.Message do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "feedback_messages" do
    field :thread_id, Ecto.UUID
    belongs_to :author, Fluently.Accounts.User, foreign_key: :author_user_id, type: Ecto.UUID
    belongs_to :reviewer, Fluently.Feedback.ProjectUser, type: Ecto.UUID
    field :body, :string
    timestamps(type: :utc_datetime_usec)
  end
end
