defmodule Fluently.Accounts.AccountMembership do
  @moduledoc "A user's role within an organizational account."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @roles ~w(owner admin member)

  schema "account_memberships" do
    field :account_id, Ecto.UUID
    field :user_id, Ecto.UUID
    field :role, :string, default: "member"
    timestamps(type: :utc_datetime_usec)
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:account_id, :user_id, :role])
    |> validate_required([:account_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:account_id, :user_id])
  end

  def owner?(%__MODULE__{role: "owner"}), do: true
  def owner?(_), do: false
  def admin?(%__MODULE__{role: role}), do: role in ["owner", "admin"]
end
