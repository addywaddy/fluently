defmodule Fluently.Accounts.AccountSession do
  @moduledoc "A login session bound to both a User and selected Account."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "account_sessions" do
    field :account_id, Ecto.UUID
    field :user_id, Ecto.UUID
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:account_id, :user_id, :token_hash, :expires_at])
    |> validate_required([:account_id, :user_id, :token_hash, :expires_at])
    |> unique_constraint(:token_hash)
  end
end
