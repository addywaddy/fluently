defmodule Fluently.Repo.Migrations.RebuildPrivateFeedbackTables do
  use Ecto.Migration

  def up do
    if private_only?() do
      # Production currently contains only disposable test feedback. Rebuild
      # these SQLite tables so direct User authorship can leave the historical
      # reviewer columns empty. Accounts, memberships, projects, and project
      # configuration are intentionally left untouched.
      drop_if_exists table(:feedback_snapshots)
      drop_if_exists table(:feedback_messages)
      drop_if_exists table(:feedback_threads)

      create table(:feedback_threads, primary_key: false) do
        add :id, :uuid, primary_key: true
        add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
        add :reviewer_id, references(:reviewers, type: :uuid)
        add :page, :text, null: false

        add :status, :string,
          null: false,
          default: "open",
          check: %{name: "valid_status", expr: "status IN ('open', 'resolved')"}

        add :anchor, :map, null: false
        add :context, :map, null: false
        add :author_user_id, references(:users, type: :uuid, on_delete: :restrict)
        timestamps(type: :utc_datetime_usec)
      end

      create index(:feedback_threads, [:project_id, :page, :status])

      create table(:feedback_messages, primary_key: false) do
        add :id, :uuid, primary_key: true

        add :thread_id, references(:feedback_threads, type: :uuid, on_delete: :delete_all),
          null: false

        add :reviewer_id, references(:reviewers, type: :uuid)
        add :body, :text, null: false
        add :author_user_id, references(:users, type: :uuid, on_delete: :restrict)
        timestamps(type: :utc_datetime_usec)
      end

      create index(:feedback_messages, [:thread_id])

      create table(:feedback_snapshots, primary_key: false) do
        add :thread_id, references(:feedback_threads, type: :uuid, on_delete: :delete_all),
          primary_key: true

        add :image, :binary, null: false
        add :width, :integer, null: false
        add :height, :integer, null: false
        timestamps(type: :utc_datetime_usec, updated_at: false)
      end
    end
  end

  def down do
    :ok
  end

  defp private_only?, do: Application.get_env(:fluently, :private_feedback_only, false)
end
