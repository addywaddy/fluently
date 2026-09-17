defmodule Fluently.Repo.Migrations.CreateFeedbackCore do
  use Ecto.Migration

  def change do
    create table(:workspaces, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :access_hash, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspaces, [:access_hash])

    create table(:projects, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :workspace_id, references(:workspaces, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :origin, :string, null: false
      add :review_hash, :binary, null: false
      add :api_hash, :binary, null: false
      add :review_expires_at, :utc_datetime_usec, null: false
      add :credential_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create index(:projects, [:workspace_id])

    create table(:reviewers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :kind, :string, null: false, default: "guest"
      add :external_id, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:reviewers, [:project_id])

    create table(:feedback_threads, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :reviewer_id, references(:reviewers, type: :uuid), null: false
      add :page, :text, null: false

      add :status, :string,
        null: false,
        default: "open",
        check: %{name: "valid_status", expr: "status IN ('open', 'resolved')"}

      add :anchor, :map, null: false
      add :context, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:feedback_threads, [:project_id, :page, :status])

    create table(:feedback_messages, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :thread_id, references(:feedback_threads, type: :uuid, on_delete: :delete_all),
        null: false

      add :reviewer_id, references(:reviewers, type: :uuid), null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:feedback_messages, [:thread_id])
  end
end
