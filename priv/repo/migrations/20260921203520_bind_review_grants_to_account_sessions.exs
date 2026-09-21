defmodule Fluently.Repo.Migrations.BindReviewGrantsToAccountSessions do
  use Ecto.Migration

  def change do
    alter table(:account_review_grants) do
      add :account_session_id, references(:account_sessions, type: :uuid, on_delete: :delete_all)
    end

    create index(:account_review_grants, [:account_session_id])

    execute """
    UPDATE account_review_grants
    SET account_session_id = (
      SELECT id FROM account_sessions
      WHERE account_sessions.account_id = account_review_grants.account_id
        AND account_sessions.token_hash = account_review_grants.account_session_hash
      LIMIT 1
    )
    WHERE account_session_id IS NULL
    """
  end
end
