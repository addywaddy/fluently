defmodule Fluently.Accounts.Invitation do
  @moduledoc "A single-use invitation to an account and selected projects."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "account_invitations" do
    field :account_id, Ecto.UUID
    field :invited_by_user_id, Ecto.UUID
    field :email, :string
    field :role, :string, default: "member"
    field :project_ids, :map, default: %{}
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :account_id,
      :invited_by_user_id,
      :email,
      :role,
      :project_ids,
      :token_hash,
      :expires_at
    ])
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> validate_required([
      :account_id,
      :invited_by_user_id,
      :email,
      :project_ids,
      :token_hash,
      :expires_at
    ])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> validate_inclusion(:role, ["member"])
    |> unique_constraint(:token_hash)
  end

  def active?(%__MODULE__{accepted_at: nil, revoked_at: nil, expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  def active?(_), do: false
end
