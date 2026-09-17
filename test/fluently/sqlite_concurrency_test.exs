defmodule Fluently.SQLiteConcurrencyTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.SQL.Sandbox
  alias Fluently.{Repo, Feedback, Threads}
  import Fluently.FeedbackFixtures

  # Real independent connections: a shared sandbox transaction would hide writer races.
  test "concurrent replies and opening-comment deletion serialize without orphan messages" do
    {owner, project, reviewer, thread} =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, owner, _} = Feedback.create_workspace("Concurrency test")

        {:ok, project, keys} =
          Feedback.create_project(owner, %{"name" => "Test", "origin" => "https://example.com"})

        {:ok, _, reviewer} = Feedback.start_review(project, keys.review, "Reviewer")
        {:ok, thread} = Threads.create(project, reviewer, attrs())
        {owner, project, reviewer, thread}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Feedback.delete_project(owner, project.id)
        Repo.delete!(owner)
      end)
    end)

    parent = self()

    operations = [
      fn -> Threads.reply(project, reviewer, thread.id, "Concurrent reply") end,
      fn -> Threads.delete_message(project, reviewer, thread.id, hd(thread.messages).id) end
    ]

    tasks =
      Enum.map(operations, fn operation ->
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> Sandbox.unboxed_run(Repo, operation)
          end
        end)
      end)

    for _ <- tasks, do: assert_receive({:ready, _})
    Enum.each(tasks, &send(&1.pid, :go))
    [reply, deletion] = Enum.map(tasks, &Task.await(&1, 10_000))
    assert match?({:ok, _}, reply) or reply == {:error, :not_found}
    assert {:ok, %{deleted_thread: true}} = deletion

    Sandbox.unboxed_run(Repo, fn ->
      refute Threads.get(project, thread.id)
      assert Repo.query!("PRAGMA foreign_key_check").rows == []
    end)
  end
end
