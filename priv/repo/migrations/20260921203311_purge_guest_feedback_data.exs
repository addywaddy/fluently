defmodule Fluently.Repo.Migrations.PurgeGuestFeedbackData do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM feedback_snapshots
    WHERE thread_id IN (
      SELECT t.id FROM feedback_threads t
      JOIN reviewers r ON r.id = t.reviewer_id
      WHERE r.kind IN ('guest', 'anonymous', 'pseudonymous')
    )
    """

    execute """
    DELETE FROM feedback_messages
    WHERE thread_id IN (
      SELECT t.id FROM feedback_threads t
      JOIN reviewers r ON r.id = t.reviewer_id
      WHERE r.kind IN ('guest', 'anonymous', 'pseudonymous')
    )
    OR reviewer_id IN (SELECT id FROM reviewers WHERE kind IN ('guest', 'anonymous', 'pseudonymous'))
    """

    execute """
    DELETE FROM feedback_threads
    WHERE reviewer_id IN (SELECT id FROM reviewers WHERE kind IN ('guest', 'anonymous', 'pseudonymous'))
    """

    execute "DELETE FROM guest_review_sessions"
    execute "DELETE FROM reviewers WHERE kind IN ('guest', 'anonymous', 'pseudonymous')"

    execute """
    DELETE FROM users
    WHERE kind = 'guest'
      AND NOT EXISTS (SELECT 1 FROM reviewers WHERE reviewers.user_id = users.id)
      AND NOT EXISTS (SELECT 1 FROM accounts WHERE accounts.user_id = users.id)
    """

    execute "DELETE FROM accounts WHERE email IS NULL"
  end

  def down do
    :ok
  end
end
