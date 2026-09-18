defmodule Fluently.IdentityMigrationTest do
  use ExUnit.Case, async: false
  alias Fluently.MigrationRepo, as: Repo

  test "migration preserves authors, credentials, private projects and snapshot bytes" do
    database = Path.join(System.tmp_dir!(), "fluently-migration-#{Ecto.UUID.generate()}.db")
    start_supervised!({Repo, database: database, pool_size: 2, journal_mode: :delete})
    on_exit(fn -> Enum.each([database, database <> "-wal", database <> "-shm"], &File.rm/1) end)
    path = Application.app_dir(:fluently, "priv/repo/migrations")
    Ecto.Migrator.run(Repo, path, :up, to: 20_260_917_202_406, log: false)
    now = "2026-09-18 12:00:00.000000"
    later = "2026-09-30 12:00:00.000000"
    sooner = "2026-09-25 12:00:00.000000"
    ids = for _ <- 1..8, do: Ecto.UUID.generate()
    [workspace, project, author, registered, guest, thread, message, staff] = ids
    timestamp = %{inserted_at: now, updated_at: now}
    insert("workspaces", timestamp, %{id: workspace, name: "Existing", access_hash: "owner-hash"})

    insert("projects", timestamp, %{
      id: project,
      workspace_id: workspace,
      name: "Private demo",
      origin: "https://example.test",
      review_hash: "review-hash",
      api_hash: "api-hash",
      review_expires_at: later
    })

    insert("reviewers", timestamp, %{
      id: author,
      project_id: project,
      name: "Guest",
      kind: "anonymous"
    })

    insert("reviewers", timestamp, %{
      id: staff,
      project_id: project,
      name: "Staff",
      kind: "account"
    })

    insert("accounts", timestamp, %{
      id: registered,
      workspace_id: workspace,
      email: "staff@example.test",
      password_hash: "password-hash",
      password_salt: "salt",
      session_hash: "registered-token",
      session_expires_at: later,
      feedback_reviewer_id: staff
    })

    insert("accounts", timestamp, %{
      id: guest,
      workspace_id: workspace,
      demo_project_id: project,
      reviewer_id: author,
      feedback_reviewer_id: author,
      session_hash: "guest-token",
      session_expires_at: later,
      expires_at: sooner
    })

    insert("feedback_threads", timestamp, %{
      id: thread,
      project_id: project,
      reviewer_id: author,
      page: "https://example.test/",
      anchor: "{}",
      context: "{}"
    })

    insert("feedback_messages", timestamp, %{
      id: message,
      thread_id: thread,
      reviewer_id: author,
      body: "Keep me"
    })

    Repo.insert_all("feedback_snapshots", [
      %{thread_id: thread, image: <<0, 1, 255>>, width: 1, height: 1, inserted_at: now}
    ])

    tables = ~w(projects feedback_threads feedback_messages feedback_snapshots)
    original = Map.new(tables, &{&1, query("SELECT * FROM #{&1}")})

    credentials =
      query("SELECT id, password_hash, password_salt, session_hash FROM accounts ORDER BY id")

    Ecto.Migrator.run(Repo, path, :up, all: true, log: false)

    assert Map.new(tables, &{&1, query("SELECT * FROM #{&1}")}) == original

    assert query(
             "SELECT id, password_hash, password_salt, session_hash FROM accounts ORDER BY id"
           ) == credentials

    assert query("SELECT user_id FROM accounts WHERE id = ?", [registered]) == [[registered]]
    assert query("SELECT user_id FROM accounts WHERE id = ?", [guest]) == [[nil]]
    assert query("SELECT user_id FROM reviewers WHERE id = ?", [author]) == [[author]]
    assert query("SELECT kind FROM users WHERE id = ?", [author]) == [["guest"]]
    assert query("SELECT kind FROM users WHERE id = ?", [registered]) == [["registered"]]

    assert query(
             "SELECT project_user_id, expires_at FROM guest_review_sessions WHERE token_hash = ?",
             ["guest-token"]
           ) == [[author, sooner]]

    assert query("SELECT project_user_id FROM guest_review_sessions WHERE token_hash = ?", [
             "registered-token"
           ]) == [[staff]]

    assert query("PRAGMA foreign_key_check") == []
    assert query("SELECT public_feedback FROM projects WHERE id = ?", [project]) == [[0]]
  end

  defp insert(table, timestamp, fields),
    do: Repo.insert_all(table, [Map.merge(timestamp, fields)])

  defp query(sql, params \\ []), do: Ecto.Adapters.SQL.query!(Repo, sql, params).rows
end
