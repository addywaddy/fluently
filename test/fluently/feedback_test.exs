defmodule Fluently.FeedbackTest do
  use Fluently.DataCase, async: true
  alias Fluently.{Feedback, Threads}

  setup do
    {:ok, owner, key} = Feedback.create_workspace("Studio")
    {:ok, other, _} = Feedback.create_workspace("Other")

    {:ok, project, keys} =
      Feedback.create_project(owner, %{"name" => "Checkout", "origin" => "https://example.com"})

    {:ok, token, reviewer} = Feedback.start_review(project, keys.review, "Jane")

    %{
      owner: owner,
      other: other,
      project: project,
      keys: keys,
      key: key,
      token: token,
      reviewer: reviewer
    }
  end

  import Fluently.FeedbackFixtures

  test "owner keys are hashed and tenant lookups are isolated", ctx do
    assert Feedback.authenticate_owner(ctx.key).id == ctx.owner.id
    refute ctx.owner.access_hash == ctx.key
    refute Feedback.authenticate_owner("wrong")
    assert Feedback.projects(ctx.other) == []
    refute Feedback.project(ctx.other, ctx.project.id)
    assert {:error, :not_found} = Feedback.rotate_project(ctx.other, ctx.project.id)
    assert {:error, :not_found} = Feedback.delete_project(ctx.other, ctx.project.id)
  end

  test "review sessions require a secret, are project scoped and revocable", ctx do
    assert {:error, :unauthorized} = Feedback.start_review(ctx.project, ctx.project.id, "Guest")
    assert {:ok, _} = Feedback.authorize(ctx.project, ctx.token)

    {:ok, other_project, _} =
      Feedback.create_project(ctx.other, %{"name" => "Other", "origin" => "https://other.com"})

    assert {:error, :unauthorized} = Feedback.authorize(other_project, ctx.token)
    {:ok, rotated, _} = Feedback.rotate_project(ctx.owner, ctx.project.id)
    assert {:error, :unauthorized} = Feedback.authorize(rotated, ctx.token)
    assert {:error, :unauthorized} = Feedback.start_review(rotated, ctx.keys.review, "Guest")
    expired = %{ctx.project | review_expires_at: DateTime.add(DateTime.utc_now(), -1)}
    assert {:error, :unauthorized} = Feedback.start_review(expired, ctx.keys.review, "Guest")
    assert {:error, :unauthorized} = Feedback.authorize(expired, ctx.token)
  end

  test "thread lifecycle persists bounded context and author identity", ctx do
    {:ok, thread} = Threads.create(ctx.project, ctx.reviewer, attrs())
    assert thread.page == "https://example.com/checkout"
    refute Map.has_key?(thread.context, "cookies")
    assert hd(thread.messages).reviewer_id == ctx.reviewer.id
    {:ok, _} = Threads.reply(ctx.project, ctx.reviewer, thread.id, "Agreed")
    {:ok, _} = Threads.status(ctx.project, thread.id, "resolved")
    assert Threads.list(ctx.project, %{"status" => "open"}) == []
    saved = Threads.get(ctx.project, thread.id)
    assert saved.status == "resolved"
    assert DateTime.compare(saved.updated_at, thread.updated_at) in [:gt, :eq]
    assert length(saved.messages) == 2
    assert Threads.serialize(saved).anchor["platform"] == "web"
    {:ok, _} = Threads.status(ctx.project, thread.id, "open")
    {:ok, _} = Threads.delete(ctx.project, thread.id)
    refute Threads.get(ctx.project, thread.id)
  end

  test "cross-project reads, writes, replies and deletions fail", ctx do
    {:ok, p, keys} =
      Feedback.create_project(ctx.other, %{"name" => "Other", "origin" => "https://other.com"})

    {:ok, _, reviewer} = Feedback.start_review(p, keys.review, "Other")
    {:ok, thread} = Threads.create(ctx.project, ctx.reviewer, attrs())
    refute Threads.get(p, thread.id)
    assert Threads.list(p, %{}) == []
    assert {:error, :unauthorized} = Threads.create(ctx.project, reviewer, attrs())
    assert {:error, :unauthorized} = Threads.reply(ctx.project, reviewer, thread.id, "bad")
    assert {:error, :not_found} = Threads.reply(p, reviewer, thread.id, "bad")
    assert {:error, :not_found} = Threads.status(p, thread.id, "resolved")
    assert {:error, :not_found} = Threads.delete(p, thread.id)
  end

  test "invalid anchors and messages are rejected atomically", ctx do
    for invalid <- [nil, [], "bad", %{}, put_in(attrs()["anchor"], ["point", "x"], 2)] do
      assert {:error, _} =
               Threads.create(ctx.project, ctx.reviewer, %{attrs() | "anchor" => invalid})
    end

    assert {:error, _} = Threads.create(ctx.project, ctx.reviewer, %{attrs() | "body" => "  "})

    assert {:error, _} =
             Threads.create(ctx.project, ctx.reviewer, %{attrs() | "page" => "https://evil.test/"})

    assert Threads.list(ctx.project, %{}) == []
  end

  test "project deletion erases all feedback and reviewers", ctx do
    {:ok, _} = Threads.create(ctx.project, ctx.reviewer, attrs())
    assert {:ok, _} = Feedback.delete_project(ctx.owner, ctx.project.id)
    assert Repo.aggregate(Fluently.Feedback.Thread, :count) == 0
    assert Repo.aggregate(Fluently.Feedback.Message, :count) == 0
    assert Repo.aggregate(Fluently.Feedback.Reviewer, :count) == 0
  end

  test "malformed URLs fail validation without raising", ctx do
    for origin <- [
          "https://example.com:bad",
          "javascript:alert(1)",
          "https://example.com/private",
          "http://example.com",
          "https://user:pass@example.com"
        ] do
      refute Feedback.valid_origin?(origin)

      assert {:error, _} =
               Feedback.create_project(ctx.owner, %{"name" => "Bad", "origin" => origin})
    end

    assert {:error, :invalid_page} = Threads.page(ctx.project, "https://example.com:bad/")
  end
end
