defmodule Fluently.GuestReviews do
  @moduledoc "Project-bound guest capabilities, independent of registered account sessions."
  import Ecto.Query
  alias Fluently.{Repo, Feedback, Threads}
  alias Fluently.Feedback.{GuestReviewSession, ProjectUser}

  def current(project, token) when not is_nil(project) and is_binary(token) do
    now = DateTime.utc_now()

    Repo.one(
      from s in GuestReviewSession,
        join: u in ProjectUser,
        on: u.id == s.project_user_id,
        where:
          u.project_id == ^project.id and s.token_hash == ^Feedback.hash(token) and
            s.expires_at > ^now,
        select: u
    ) || transition_legacy_guest(project, token, now)
  end

  def current(_, _), do: nil

  # Cover requests completed by the old release after the migration ran. Only
  # anonymous accounts qualify: a registered login must never recover guest access.
  defp transition_legacy_guest(project, token, now) do
    alias Fluently.Accounts.{Account, User}

    legacy =
      Repo.one(
        from a in Account,
          join: u in ProjectUser,
          on: u.id == a.feedback_reviewer_id,
          where:
            is_nil(a.email) and a.session_hash == ^Feedback.hash(token) and
              a.session_expires_at > ^now and a.expires_at > ^now and u.project_id == ^project.id,
          select: {a, u}
      )

    case legacy do
      {account, identity} ->
        {:ok, identity} =
          Repo.transaction(fn ->
            identity =
              if is_nil(identity.user_id) do
                Repo.insert!(%User{id: identity.id, kind: "guest"}, on_conflict: :nothing)
                identity |> Ecto.Changeset.change(user_id: identity.id) |> Repo.update!()
              else
                identity
              end

            Repo.insert!(
              %GuestReviewSession{
                project_user_id: identity.id,
                token_hash: Feedback.hash(token),
                expires_at: Enum.min([account.expires_at, account.session_expires_at], DateTime)
              },
              on_conflict: :nothing,
              conflict_target: :token_hash
            )

            identity
          end)

        identity

      nil ->
        nil
    end
  end

  def prune_expired do
    now = DateTime.utc_now()
    Repo.delete_all(from s in GuestReviewSession, where: s.expires_at <= ^now)
  end

  def create_comment(project, token, attrs) do
    Repo.transaction(fn ->
      {identity, token} =
        case current(project, token) do
          nil ->
            {:ok, identity} =
              Feedback.create_project_user(project, %{name: "Guest", kind: "anonymous"})

            token = Feedback.secret()

            Repo.insert!(%GuestReviewSession{
              project_user_id: identity.id,
              token_hash: Feedback.hash(token),
              expires_at: DateTime.add(DateTime.utc_now(), 14, :day)
            })

            {identity, token}

          identity ->
            {identity, token}
        end

      case Threads.create(project, identity, attrs) do
        {:ok, thread} -> %{thread: thread, identity: identity, token: token}
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end
end
