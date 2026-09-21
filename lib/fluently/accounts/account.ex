defmodule Fluently.Accounts.Account do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "accounts" do
    field :user_id, Ecto.UUID
    field :workspace_id, Ecto.UUID
    field :demo_project_id, Ecto.UUID
    field :reviewer_id, Ecto.UUID
    field :feedback_reviewer_id, Ecto.UUID
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :binary, redact: true
    field :password_salt, :binary, redact: true
    field :session_hash, :binary, redact: true
    field :session_expires_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    has_many :memberships, Fluently.Accounts.AccountMembership
    timestamps(type: :utc_datetime_usec)
  end
end
