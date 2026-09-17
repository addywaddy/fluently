defmodule Fluently.Threads do
  @moduledoc "Project-scoped conversations. Mutations derive authorship from the authorized reviewer."
  import Ecto.Query
  import Ecto.Changeset
  alias Fluently.Repo
  alias Fluently.Feedback.{Thread, Message, Anchor, Reviewer}

  def list(project, params) do
    query =
      from t in Thread,
        where: t.project_id == ^project.id,
        order_by: [asc: t.inserted_at, asc: t.id]

    query =
      if params["status"] in ["open", "resolved"],
        do: where(query, [t], t.status == ^params["status"]),
        else: query

    query =
      if is_binary(params["page"]), do: where(query, [t], t.page == ^params["page"]), else: query

    offset = offset(params["offset"])
    query |> limit(100) |> offset(^offset) |> Repo.all() |> preload()
  end

  def offset(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 and n <= 100_000 -> n
      _ -> 0
    end
  end

  def offset(_), do: 0

  def get(project, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.one(from t in Thread, where: t.project_id == ^project.id and t.id == ^id)
        |> preload()

      _ ->
        nil
    end
  end

  def create(project, %Reviewer{project_id: pid} = reviewer, attrs) when pid == project.id do
    with {:ok, anchor} <- Anchor.normalize(attrs["anchor"]),
         {:ok, context} <- Anchor.context(attrs["context"]),
         {:ok, page} <- page(project, attrs["page"]) do
      Repo.transaction(fn ->
        thread =
          %Thread{
            project_id: project.id,
            reviewer_id: reviewer.id,
            page: page,
            anchor: anchor,
            context: context
          }
          |> Repo.insert!()

        case add_message(thread, reviewer, attrs["body"]) do
          {:ok, _} -> preload(thread)
          {:error, error} -> Repo.rollback(error)
        end
      end)
    end
  end

  def create(_, _, _), do: {:error, :unauthorized}

  def reply(project, %Reviewer{project_id: pid} = reviewer, id, body) when pid == project.id do
    case get(project, id) do
      nil ->
        {:error, :not_found}

      thread ->
        Repo.transaction(fn ->
          case add_message(thread, reviewer, body) do
            {:ok, message} ->
              Repo.update_all(
                from(t in Thread, where: t.id == ^thread.id and t.project_id == ^project.id),
                set: [updated_at: DateTime.utc_now()]
              )

              message

            {:error, error} ->
              Repo.rollback(error)
          end
        end)
    end
  end

  def reply(_, _, _, _), do: {:error, :unauthorized}

  def status(project, id, status) when status in ["open", "resolved"] do
    case get(project, id) do
      nil -> {:error, :not_found}
      thread -> thread |> change(status: status) |> Repo.update()
    end
  end

  def status(_, _, _), do: {:error, :invalid_status}

  def delete(project, id) do
    case get(project, id) do
      nil -> {:error, :not_found}
      thread -> Repo.delete(thread)
    end
  end

  def serialize(thread) do
    %{
      id: thread.id,
      project_id: thread.project_id,
      page: thread.page,
      status: thread.status,
      anchor: thread.anchor,
      context: thread.context,
      created_at: thread.inserted_at,
      updated_at: thread.updated_at,
      messages:
        Enum.map(thread.messages, fn m ->
          %{
            id: m.id,
            body: m.body,
            created_at: m.inserted_at,
            author: %{id: m.reviewer.id, name: m.reviewer.name, kind: m.reviewer.kind}
          }
        end)
    }
  end

  def page(project, value) when is_binary(value) and byte_size(value) <= 2000 do
    with {:ok, uri} <- URI.new(value),
         origin = URI.to_string(%{uri | path: nil, query: nil, fragment: nil}),
         true <- origin == project.origin and uri.userinfo == nil do
      {:ok, project.origin <> (uri.path || "/")}
    else
      _ -> {:error, :invalid_page}
    end
  end

  def page(_, _), do: {:error, :invalid_page}

  defp add_message(thread, reviewer, body) do
    %Message{thread_id: thread.id, reviewer_id: reviewer.id}
    |> cast(%{body: body}, [:body])
    |> validate_required([:body])
    |> validate_length(:body, max: 4000)
    |> Repo.insert()
  end

  defp preload(nil), do: nil

  defp preload(value),
    do:
      Repo.preload(value,
        messages: {from(m in Message, order_by: [asc: m.inserted_at, asc: m.id]), [:reviewer]}
      )
end
