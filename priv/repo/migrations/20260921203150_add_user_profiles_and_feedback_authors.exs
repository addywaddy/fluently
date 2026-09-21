defmodule Fluently.Repo.Migrations.AddUserProfilesAndFeedbackAuthors do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :name, :string
      add :email, :string
    end

    create unique_index(:users, [:email], where: "email IS NOT NULL")

    alter table(:feedback_threads) do
      add :author_user_id, references(:users, type: :uuid, on_delete: :restrict)
    end

    alter table(:feedback_messages) do
      add :author_user_id, references(:users, type: :uuid, on_delete: :restrict)
    end

    execute """
    UPDATE users
    SET name = (SELECT name FROM accounts WHERE accounts.user_id = users.id),
        email = (SELECT email FROM accounts WHERE accounts.user_id = users.id)
    WHERE EXISTS (SELECT 1 FROM accounts WHERE accounts.user_id = users.id)
    """

    execute """
    UPDATE feedback_threads
    SET author_user_id = (SELECT user_id FROM reviewers WHERE reviewers.id = feedback_threads.reviewer_id)
    WHERE EXISTS (SELECT 1 FROM reviewers WHERE reviewers.id = feedback_threads.reviewer_id AND reviewers.user_id IS NOT NULL)
    """

    execute """
    UPDATE feedback_messages
    SET author_user_id = (SELECT user_id FROM reviewers WHERE reviewers.id = feedback_messages.reviewer_id)
    WHERE EXISTS (SELECT 1 FROM reviewers WHERE reviewers.id = feedback_messages.reviewer_id AND reviewers.user_id IS NOT NULL)
    """
  end
end
