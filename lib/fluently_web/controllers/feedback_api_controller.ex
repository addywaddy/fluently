defmodule FluentlyWeb.FeedbackAPIController do
  use FluentlyWeb, :controller
  alias Fluently.{Feedback, Threads, RateLimit}
  plug :project_boundary
  plug :authenticate when action not in [:options, :session, :account_session]

  plug :thread_boundary when action not in [:options, :session, :account_session]

  def options(conn, _), do: send_resp(conn, 204, "")

  def session(conn, params) do
    if RateLimit.allow?({:exchange, conn.remote_ip}, 20) and
         RateLimit.allow?({:project_exchange, conn.assigns.project.id}, 60) do
      case Feedback.start_review(
             conn.assigns.project,
             params["token"],
             params["name"],
             params["external_ref"]
           ) do
        {:ok, token, reviewer} ->
          json(conn, %{
            token: token,
            expires_in: 86_400,
            reviewer: %{id: reviewer.id, name: reviewer.name}
          })

        {:error, :invalid_reference} ->
          error(
            conn,
            422,
            "Customer reference must contain 1–200 letters, digits, underscores or hyphens"
          )

        {:error, :unauthorized} ->
          error(conn, 401, "Review invitation is invalid or expired")

        _ ->
          error(conn, 422, "Enter a display name of 1–80 characters")
      end
    else
      error(conn, 429, "Too many attempts; try again in a minute")
    end
  end

  def account_session(conn, params) do
    if get_req_header(conn, "origin") == [conn.assigns.project.origin] and
         RateLimit.allow?({:account_exchange, conn.remote_ip}, 20) and
         RateLimit.allow?({:project_account_exchange, conn.assigns.project.id}, 60) do
      case Fluently.AccountReviews.exchange(
             conn.assigns.project,
             params["code"],
             params["verifier"]
           ) do
        {:ok, %{token: token, identity: user}} ->
          json(conn, %{
            token: token,
            expires_in: 86_400,
            reviewer: %{id: user.id, name: user.name, kind: "account"}
          })

        _ ->
          error(
            conn,
            401,
            "Review connection expired or unavailable. Connect again or use a guest invitation."
          )
      end
    else
      error(conn, 403, "Review connection unavailable")
    end
  end

  def end_session(conn, _) do
    ["Bearer " <> token] = get_req_header(conn, "authorization")
    Fluently.AccountReviews.revoke(conn.assigns.project, token)
    send_resp(conn, 204, "")
  end

  def index(conn, params) do
    if (is_nil(params["status"]) or params["status"] in ["open", "resolved"]) and
         params["view"] in [nil, "all", "mine"] do
      threads = Threads.list(conn.assigns.project, params, list_scope(conn, params))

      json(conn, %{
        identity:
          if(conn.assigns.reviewer,
            do: %{
              name: conn.assigns.reviewer.name,
              kind: if(conn.assigns.reviewer.account_member, do: "account", else: "guest")
            },
            else: nil
          ),
        data: Enum.map(threads, &serialize(conn, &1)),
        next_offset:
          if(length(threads) == 100, do: Threads.offset(params["offset"]) + 100, else: nil)
      })
    else
      error(conn, 422, "status must be open or resolved; view must be all or mine")
    end
  end

  def show(conn, %{"thread_id" => id}) do
    case Threads.get(conn.assigns.project, id) do
      nil -> error(conn, 404, "Not found")
      thread -> json(conn, %{data: serialize(conn, thread)})
    end
  end

  def create(conn, params) do
    case Threads.create(conn.assigns.project, conn.assigns.reviewer, params) do
      {:ok, thread} ->
        conn |> put_status(201) |> json(%{data: serialize(conn, thread)})

      _ ->
        error(conn, 422, "Invalid comment, page, anchor or context")
    end
  end

  def snapshot(conn, %{"thread_id" => id}) do
    with project when not is_nil(project) <- conn.assigns.project,
         snapshot when not is_nil(snapshot) <- Fluently.Snapshots.get(project, id) do
      json(conn, %{data: Fluently.Snapshots.serialize(snapshot)})
    else
      _ -> error(conn, 404, "Snapshot not found")
    end
  end

  def attach_snapshot(conn, %{"thread_id" => id} = params) do
    with project when not is_nil(project) <- conn.assigns.project,
         {:ok, _} <-
           Fluently.Snapshots.attach(project, conn.assigns.reviewer, id, params["data_url"]) do
      json(conn, %{data: serialize(conn, Threads.get(project, id))})
    else
      {:error, :invalid_image} ->
        error(conn, 422, "Use a PNG up to 200 KiB and 1200 × 1200 pixels")

      _ ->
        error(conn, 404, "Comment not found or not yours")
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
              do: serialize(conn, result.thread),
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

  defp serialize(conn, thread) do
    reviewer = conn.assigns.reviewer

    Threads.serialize(thread, reviewer,
      reference_metadata: is_nil(reviewer) or reviewer.account_member
    )
  end

  defp list_scope(conn, %{"view" => "mine"}) do
    if conn.assigns.reviewer, do: conn.assigns.reviewer.id, else: :none
  end

  defp list_scope(conn, _), do: scope(conn)

  defp scope(conn) do
    if conn.assigns.project.public_feedback && conn.assigns.reviewer &&
         not conn.assigns.reviewer.account_member,
       do: conn.assigns.reviewer.id,
       else: :all
  end

  defp thread_boundary(conn, _) do
    if conn.params["thread_id"] &&
         not Threads.visible?(conn.assigns.project, conn.params["thread_id"], scope(conn)),
       do: conn |> error(404, "Not found") |> halt(),
       else: conn
  end

  defp error(conn, status, message),
    do: conn |> put_status(status) |> json(%{error: %{message: message}})
end
