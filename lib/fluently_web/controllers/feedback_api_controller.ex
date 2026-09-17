defmodule FluentlyWeb.FeedbackAPIController do
  use FluentlyWeb, :controller
  alias Fluently.{Feedback, Threads, RateLimit}
  plug :project_boundary
  plug :authenticate when action not in [:options, :session]

  def options(conn, _), do: send_resp(conn, 204, "")

  def session(conn, params) do
    if RateLimit.allow?({:exchange, conn.remote_ip}, 20) and
         RateLimit.allow?({:project_exchange, conn.assigns.project.id}, 60) do
      case Feedback.start_review(conn.assigns.project, params["token"], params["name"]) do
        {:ok, token, reviewer} ->
          json(conn, %{
            token: token,
            expires_in: 86_400,
            reviewer: %{id: reviewer.id, name: reviewer.name}
          })

        {:error, :unauthorized} ->
          error(conn, 401, "Review invitation is invalid or expired")

        _ ->
          error(conn, 422, "Enter a display name of 1–80 characters")
      end
    else
      error(conn, 429, "Too many attempts; try again in a minute")
    end
  end

  def index(conn, params) do
    if is_nil(params["status"]) or params["status"] in ["open", "resolved"] do
      threads = Threads.list(conn.assigns.project, params)

      json(conn, %{
        data: Enum.map(threads, &Threads.serialize(&1, conn.assigns.reviewer)),
        next_offset:
          if(length(threads) == 100, do: Threads.offset(params["offset"]) + 100, else: nil)
      })
    else
      error(conn, 422, "status must be open or resolved")
    end
  end

  def show(conn, %{"thread_id" => id}) do
    case Threads.get(conn.assigns.project, id) do
      nil -> error(conn, 404, "Not found")
      thread -> json(conn, %{data: Threads.serialize(thread, conn.assigns.reviewer)})
    end
  end

  def create(conn, params) do
    case Threads.create(conn.assigns.project, conn.assigns.reviewer, params) do
      {:ok, thread} ->
        conn |> put_status(201) |> json(%{data: Threads.serialize(thread, conn.assigns.reviewer)})

      _ ->
        error(conn, 422, "Invalid comment, page, anchor or context")
    end
  end

  def reply(conn, %{"thread_id" => id} = params) do
    case Threads.reply(conn.assigns.project, conn.assigns.reviewer, id, params["body"]) do
      {:ok, _} -> show(conn, %{"thread_id" => id})
      {:error, :not_found} -> error(conn, 404, "Not found")
      _ -> error(conn, 422, "Comment must contain 1–4000 characters")
    end
  end

  def update(conn, %{"thread_id" => id} = params) do
    case Threads.status(conn.assigns.project, id, params["status"]) do
      {:ok, _} -> show(conn, %{"thread_id" => id})
      {:error, :not_found} -> error(conn, 404, "Not found")
      _ -> error(conn, 422, "status must be open or resolved")
    end
  end

  def delete_message(conn, %{"thread_id" => id, "message_id" => message_id}) do
    case Threads.delete_message(conn.assigns.project, conn.assigns.reviewer, id, message_id) do
      {:ok, result} ->
        json(conn, %{
          deleted_thread: result.deleted_thread,
          data:
            if(result.thread,
              do: Threads.serialize(result.thread, conn.assigns.reviewer),
              else: nil
            )
        })

      _ ->
        error(conn, 404, "Comment not found or not yours to delete")
    end
  end

  defp project_boundary(conn, _) do
    conn =
      conn |> put_resp_header("cache-control", "no-store") |> put_resp_header("vary", "Origin")

    project = Feedback.project(conn.params["id"])
    origin = get_req_header(conn, "origin")

    cond do
      is_nil(project) ->
        conn |> error(404, "Not found") |> halt()

      origin != [] and origin != [project.origin] ->
        conn |> error(403, "Origin not allowed") |> halt()

      true ->
        conn = assign(conn, :project, project)

        if origin == [] do
          conn
        else
          conn
          |> put_resp_header("access-control-allow-origin", project.origin)
          |> put_resp_header("access-control-allow-methods", "GET, POST, PATCH, DELETE, OPTIONS")
          |> put_resp_header("access-control-allow-headers", "authorization, content-type")
          |> put_resp_header("access-control-max-age", "600")
        end
    end
  end

  defp authenticate(conn, _) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _ -> nil
      end

    project = conn.assigns.project
    result = Feedback.authorize(project, token)
    read_key = Feedback.valid_secret?(token, project.api_hash)

    cond do
      read_key and conn.method != "GET" ->
        conn |> error(403, "API key is read-only") |> halt()

      not read_key and not match?({:ok, _}, result) ->
        conn |> error(401, "Valid review session or read API key required") |> halt()

      not RateLimit.allow?(
        {:api, conn.method == "GET", project.id, Feedback.hash(token)},
        if(conn.method == "GET", do: 180, else: 40)
      ) ->
        conn |> error(429, "Rate limit reached; try again in a minute") |> halt()

      read_key ->
        assign(conn, :reviewer, nil)

      true ->
        {:ok, reviewer} = result
        assign(conn, :reviewer, reviewer)
    end
  end

  defp error(conn, status, message),
    do: conn |> put_status(status) |> json(%{error: %{message: message}})
end
