defmodule Fluently.Repo.Migrations.AddAccountAndProjectMemberships do
  use Ecto.Migration

  def change do
    create table(:account_memberships, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :role, :string,
        null: false,
        default: "member",
        check: %{name: "account_membership_role", expr: "role IN ('owner', 'admin', 'member')"}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_memberships, [:account_id, :user_id])
    create index(:account_memberships, [:user_id])

    create table(:project_memberships, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_memberships, [:project_id, :user_id])
    create index(:project_memberships, [:user_id])

    execute """
    INSERT INTO account_memberships (id, account_id, user_id, role, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))), id, user_id, 'owner', inserted_at, updated_at
    FROM accounts WHERE user_id IS NOT NULL
    """

    execute """
    INSERT INTO project_memberships (id, project_id, user_id, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))), pa.project_id, r.user_id, r.inserted_at, r.updated_at
    FROM project_admins pa JOIN reviewers r ON r.id = pa.reviewer_id WHERE r.user_id IS NOT NULL
    """
  end
end
