defmodule Fluently.Feedback.GuestReviewSession do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "guest_review_sessions" do
    field :project_user_id, Ecto.UUID
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
