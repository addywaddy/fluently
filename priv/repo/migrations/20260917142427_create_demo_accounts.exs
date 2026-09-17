defmodule Fluently.Repo.Migrations.CreateDemoAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :workspace_id, references(:workspaces, type: :uuid, on_delete: :delete_all), null: false
      add :demo_project_id, references(:projects, type: :uuid, on_delete: :nilify_all)
      add :reviewer_id, references(:reviewers, type: :uuid, on_delete: :nilify_all)
      add :email, :string
      add :name, :string
      add :password_hash, :binary
      add :password_salt, :binary
      add :session_hash, :binary
      add :session_expires_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:accounts, [:email])
    create unique_index(:accounts, [:session_hash])
    create index(:accounts, [:expires_at])
  end
end
