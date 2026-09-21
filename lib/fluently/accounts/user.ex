defmodule Fluently.Accounts.User do
  @moduledoc "A person identity with profile fields independent of account membership."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :kind, :string, default: "guest"
    field :name, :string
    field :email, :string
    has_many :account_memberships, Fluently.Accounts.AccountMembership
    has_many :project_memberships, Fluently.Feedback.ProjectMembership
    timestamps(type: :utc_datetime_usec)
  end
end
