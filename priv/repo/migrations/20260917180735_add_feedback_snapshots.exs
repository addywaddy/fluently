defmodule Fluently.Repo.Migrations.AddFeedbackSnapshots do
  use Ecto.Migration

  def change do
    create table(:feedback_snapshots, primary_key: false) do
      add :thread_id, references(:feedback_threads, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :image, :binary, null: false
      add :width, :integer, null: false
      add :height, :integer, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end
end
