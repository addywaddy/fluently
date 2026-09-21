defmodule Fluently.Repo.Migrations.CreateAccountInvitations do
  use Ecto.Migration

  def change do
    create table(:account_invitations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false
      add :invited_by_user_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :email, :string, null: false

      add :role, :string,
        null: false,
        default: "member",
        check: %{name: "account_invitation_role", expr: "role IN ('member')"}

      add :project_ids, :map, null: false, default: %{}
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_invitations, [:token_hash])
    create index(:account_invitations, [:account_id, :email])
    create index(:account_invitations, [:expires_at])
  end
end
