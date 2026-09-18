defmodule Fluently.Repo.Migrations.SeparateUsersAndGuestReviewSessions do
  use Ecto.Migration

  def up do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :kind, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    alter table(:accounts) do
      add :user_id, references(:users, type: :uuid, on_delete: :restrict)
    end

    alter table(:reviewers) do
      add :user_id, references(:users, type: :uuid, on_delete: :restrict)
    end

    create unique_index(:accounts, [:user_id])
    create index(:reviewers, [:project_id, :user_id])

    create table(:guest_review_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :project_user_id, references(:reviewers, type: :uuid, on_delete: :delete_all),
        null: false

      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:guest_review_sessions, [:token_hash])

    execute "INSERT INTO users (id, kind, inserted_at, updated_at) SELECT id, 'registered', inserted_at, updated_at FROM accounts WHERE email IS NOT NULL"
    execute "UPDATE accounts SET user_id = id WHERE email IS NOT NULL"

    execute "INSERT INTO users (id, kind, inserted_at, updated_at) SELECT id, 'guest', inserted_at, updated_at FROM reviewers"

    execute "UPDATE reviewers SET user_id = id"

    # Preserve browser capabilities, not account ownership of guest feedback.
    # A later login rotates account secrets and cannot recover these guest sessions.
    execute """
    INSERT INTO guest_review_sessions (id, project_user_id, token_hash, expires_at, inserted_at, updated_at)
    SELECT id, feedback_reviewer_id, session_hash,
      CASE WHEN expires_at IS NOT NULL AND expires_at < session_expires_at
        THEN expires_at ELSE session_expires_at END,
      inserted_at, updated_at
    FROM accounts
    WHERE feedback_reviewer_id IS NOT NULL AND session_hash IS NOT NULL AND session_expires_at IS NOT NULL
    """
  end

  def down do
    drop table(:guest_review_sessions)
    drop index(:reviewers, [:project_id, :user_id])
    alter table(:reviewers), do: remove(:user_id)
    drop index(:accounts, [:user_id])
    alter table(:accounts), do: remove(:user_id)
    drop table(:users)
  end
end
