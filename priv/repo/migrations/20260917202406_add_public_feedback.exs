defmodule Fluently.Repo.Migrations.AddPublicFeedback do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :public_feedback, :boolean, null: false, default: false
    end

    alter table(:accounts) do
      add :feedback_reviewer_id, references(:reviewers, type: :uuid, on_delete: :nilify_all)
    end

    create table(:project_admins, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :workspace_id, references(:workspaces, type: :uuid, on_delete: :delete_all), null: false
      add :reviewer_id, references(:reviewers, type: :uuid, on_delete: :nilify_all)
    end

    create unique_index(:project_admins, [:project_id, :workspace_id])

    # Explicitly opt in the two existing first-party installations only.
    execute "UPDATE projects SET public_feedback = 1 WHERE (id = 'bfef5446-e12f-40d1-96db-dced5bf805e1' AND origin = 'https://fluently.now') OR (id = 'de78e976-1134-42b3-ad66-ac96136c3d31' AND origin = 'http://localhost:4000')",
            "UPDATE projects SET public_feedback = 0"
  end
end
