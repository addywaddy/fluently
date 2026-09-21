defmodule Fluently.Repo.Migrations.AddAccountSessions do
  use Ecto.Migration

  def change do
    create table(:account_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_sessions, [:token_hash])
    create index(:account_sessions, [:account_id, :user_id])
    create index(:account_sessions, [:expires_at])

    execute """
    INSERT INTO account_sessions (id, account_id, user_id, token_hash, expires_at, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))), id, user_id, session_hash, session_expires_at, inserted_at, updated_at
    FROM accounts
    WHERE user_id IS NOT NULL AND session_hash IS NOT NULL AND session_expires_at IS NOT NULL
    """
  end
end
