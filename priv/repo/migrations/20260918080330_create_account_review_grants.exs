defmodule Fluently.Repo.Migrations.CreateAccountReviewGrants do
  use Ecto.Migration

  def change do
    create table(:account_review_grants, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false

      add :membership_id, references(:project_admins, type: :uuid, on_delete: :delete_all),
        null: false

      add :account_session_hash, :binary, null: false
      add :credential_version, :integer, null: false
      add :challenge, :string, null: false
      add :code_hash, :binary
      add :token_hash, :binary
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_review_grants, [:code_hash])
    create unique_index(:account_review_grants, [:token_hash])
    create index(:account_review_grants, [:expires_at])
  end
end
