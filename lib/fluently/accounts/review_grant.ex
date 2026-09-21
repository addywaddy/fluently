defmodule Fluently.Accounts.ReviewGrant do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "account_review_grants" do
    field :project_id, Ecto.UUID
    field :account_id, Ecto.UUID
    field :account_session_id, Ecto.UUID
    field :membership_id, Ecto.UUID
    field :account_session_hash, :binary, redact: true
    field :credential_version, :integer
    field :challenge, :string
    field :code_hash, :binary, redact: true
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
