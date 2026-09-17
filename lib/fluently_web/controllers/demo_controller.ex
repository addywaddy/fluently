defmodule FluentlyWeb.DemoController do
  use FluentlyWeb, :controller
  alias Fluently.{Accounts, Threads, RateLimit}
  plug :boundary
  plug :thread_boundary

  def index(conn, params) do
    project = Accounts.demo_project(conn.assigns.account)

    threads =
      if project,
        do:
          Threads.list(
            project,
            Map.put(params, "page", project.origin <> "/"),
            visitor_scope(conn)
          ),
        else: []

    json(conn, %{
      data: Enum.map(threads, &serialize(conn, &1, reviewer(conn.assigns.account))),
      registered: registered?(conn.assigns.account),
      next_offset:
        if(length(threads) == 100, do: Threads.offset(params["offset"]) + 100, else: nil)
    })
  end

  def create(conn, params) do
    # Only the landing page is a public demo, never arbitrary customer pages.
    project = Accounts.demo_project(conn.assigns.account)
    origin = if project, do: project.origin, else: request_origin(conn)
    params = Map.put(params, "page", origin <> "/")

    case Accounts.first_comment(conn.assigns.account, params, origin) do
      {:ok, %{token: token, thread: thread, account: account}} ->
        conn =
          if token,
            do: conn |> configure_session(renew: true) |> put_session(:account_token, token),
            else: conn

        conn
        |> put_status(201)
        |> json(%{data: serialize(conn, thread, Accounts.reviewer(account))})

      _ ->
        error(conn, 422, "Could not save your comment. Check the text or reload and try again.")
    end
  end

  def snapshot(conn, %{"thread_id" => id}) do
    with project when not is_nil(project) <- Accounts.demo_project(conn.assigns.account),
         snapshot when not is_nil(snapshot) <- Fluently.Snapshots.get(project, id) do
      json(conn, %{data: Fluently.Snapshots.serialize(snapshot)})
    else
      _ -> error(conn, 404, "Snapshot not found")
    end
  end

  def attach_snapshot(conn, %{"thread_id" => id} = params) do
    with project when not is_nil(project) <- Accounts.demo_project(conn.assigns.account),
         {:ok, _} <-
           Fluently.Snapshots.attach(
             project,
             reviewer(conn.assigns.account),
             id,
             params["data_url"]
           ) do
      json(conn, %{
        data: serialize(conn, Threads.get(project, id), reviewer(conn.assigns.account))
      })
    else
      {:error, :invalid_image} ->
        error(conn, 422, "Use a PNG up to 200 KiB and 1200 × 1200 pixels")

      _ ->
        error(conn, 404, "Comment not found or not yours")
    end
  end

  def reply(conn, %{"thread_id" => id} = params) do
    with project when not is_nil(project) <- Accounts.demo_project(conn.assigns.account),
         {:ok, _} <- Threads.reply(project, reply_reviewer(conn), id, params["body"]) do
      json(conn, %{data: serialize(conn, Threads.get(project, id), reply_reviewer(conn))})
    else
      {:error, %Ecto.Changeset{}} -> error(conn, 422, "Write a reply of 1–4000 characters.")
      _ -> error(conn, 404, "Not found")
    end
  end

  def update(conn, %{"thread_id" => id} = params) do
    with project when not is_nil(project) <- Accounts.demo_project(conn.assigns.account),
         {:ok, _} <- Threads.status(project, id, params["status"]) do
      json(conn, %{
        data: serialize(conn, Threads.get(project, id), reviewer(conn.assigns.account))
      })
    else
      {:error, :invalid_status} -> error(conn, 422, "Invalid status")
      _ -> error(conn, 404, "Not found")
    end
  end

  def delete_message(conn, %{"thread_id" => id, "message_id" => message_id}) do
    with project when not is_nil(project) <- Accounts.demo_project(conn.assigns.account),
         thread when not is_nil(thread) <- Threads.get(project, id),
         message when not is_nil(message) <- Enum.find(thread.messages, &(&1.id == message_id)),
         author when not is_nil(author) <-
           Enum.find(reviewers(conn), &(&1.id == message.reviewer_id)),
         {:ok, result} <- Threads.delete_message(project, author, id, message_id) do
      json(conn, %{
        deleted_thread: result.deleted_thread,
        data:
          if(result.thread,
            do: serialize(conn, result.thread, reviewer(conn.assigns.account)),
            else: nil
          )
      })
    else
      _ -> error(conn, 404, "Comment not found or not yours to delete")
    end
  end

  # Storage uses the project's canonical origin. The browser may use
  # another address for this same app (e.g. 127.0.0.1 instead of localhost).
  defp serialize(conn, thread, reviewer) do
    ids = Enum.map([reviewer | reviewers(conn)] |> Enum.reject(&is_nil/1), & &1.id)

    thread
    |> Threads.serialize(reviewer)
    |> Map.put(:page, request_origin(conn) <> "/")
    |> Map.update!(:messages, fn messages ->
      Enum.map(messages, &Map.put(&1, :can_delete, &1.author.id in ids))
    end)
  end

  defp reviewers(conn) do
    own = reviewer(conn.assigns.account)

    admin =
      if visitor_scope(conn) == :all do
        Fluently.ProjectAccess.existing_reviewer(
          admin_workspace(conn),
          Accounts.demo_project(conn.assigns.account)
        )
      end

    Enum.reject([own, admin], &is_nil/1)
  end

  defp request_origin(conn) do
    # Production terminates TLS at Kamal. Use the configured public origin,
    # independent of the transport host/port presented by the reverse proxy.
    Application.get_env(:fluently, :canonical_feedback_origin) ||
      conn
      |> request_url()
      |> URI.parse()
      |> Map.merge(%{path: nil, query: nil, fragment: nil})
      |> URI.to_string()
  end

  defp reviewer(nil), do: nil
  defp reviewer(account), do: Accounts.reviewer(account)

  defp boundary(conn, _) do
    conn = put_resp_header(conn, "cache-control", "no-store")
    account = Accounts.current(get_session(conn, :account_token))

    cond do
      not Accounts.demo_enabled?() ->
        conn |> error(404, "Demo unavailable") |> halt()

      get_req_header(conn, "origin") not in [[], [request_origin(conn)]] ->
        conn |> error(403, "Origin not allowed") |> halt()

      not RateLimit.allow?(
        {:demo_ip, conn.remote_ip, conn.method == "GET"},
        if(conn.method == "GET", do: 180, else: 30)
      ) ->
        conn |> error(429, "Too many requests. Try again in a minute.") |> halt()

      account &&
          not RateLimit.allow?(
            {:demo_account, account.id, conn.method == "GET"},
            if(conn.method == "GET", do: 180, else: 40)
          ) ->
        conn |> error(429, "Too many requests. Try again in a minute.") |> halt()

      true ->
        assign(conn, :account, account)
    end
  end

  defp visitor_scope(conn) do
    account = conn.assigns.account
    project = Accounts.demo_project(account)

    workspace = admin_workspace(conn)

    cond do
      workspace && project && Fluently.ProjectAccess.project(workspace, project.id) -> :all
      reviewer(account) -> reviewer(account).id
      true -> :none
    end
  end

  defp admin_workspace(conn) do
    account = conn.assigns.account

    if account && account.email do
      Fluently.Feedback.workspace(account.workspace_id)
    else
      with {:ok, id} <-
             Phoenix.Token.verify(
               FluentlyWeb.Endpoint,
               "owner-v1",
               get_session(conn, :owner) || "",
               max_age: 43_200
             ) do
        Fluently.Feedback.workspace(id)
      else
        _ -> nil
      end
    end
  end

  defp reply_reviewer(conn) do
    if visitor_scope(conn) == :all do
      {:ok, reviewer} =
        Fluently.ProjectAccess.reviewer(
          admin_workspace(conn),
          Accounts.demo_project(conn.assigns.account)
        )

      reviewer
    else
      reviewer(conn.assigns.account)
    end
  end

  defp thread_boundary(conn, _) do
    if conn.params["thread_id"] do
      project = Accounts.demo_project(conn.assigns.account)

      if project && Threads.visible?(project, conn.params["thread_id"], visitor_scope(conn)),
        do: conn,
        else: conn |> error(404, "Not found") |> halt()
    else
      conn
    end
  end

  defp registered?(nil), do: false
  defp registered?(account), do: not is_nil(account.email)

  defp error(conn, status, message),
    do: conn |> put_status(status) |> json(%{error: %{message: message}})
end
