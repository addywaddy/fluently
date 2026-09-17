defmodule FluentlyWeb.DemoController do
  use FluentlyWeb, :controller
  alias Fluently.{Accounts, Threads, RateLimit}
  plug :boundary

  def index(conn, params) do
    project = Accounts.demo_project(conn.assigns.account)

    threads =
      if project,
        do: Threads.list(project, Map.put(params, "page", project.origin <> "/")),
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
    project = Accounts.demo_project(conn.assigns.account) || conn.assigns.template
    params = Map.put(params, "page", project.origin <> "/")

    case Accounts.first_comment(conn.assigns.account, params) do
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
    with account when not is_nil(account) <- conn.assigns.account,
         project when not is_nil(project) <- Accounts.demo_project(account),
         {:ok, _} <- Threads.reply(project, Accounts.reviewer(account), id, params["body"]) do
      json(conn, %{data: serialize(conn, Threads.get(project, id), Accounts.reviewer(account))})
    else
      {:error, %Ecto.Changeset{}} -> error(conn, 422, "Write a reply of 1–4000 characters.")
      _ -> error(conn, 404, "Not found")
    end
  end

  def update(conn, %{"thread_id" => id} = params) do
    with account when not is_nil(account) <- conn.assigns.account,
         project when not is_nil(project) <- Accounts.demo_project(account),
         {:ok, _} <- Threads.status(project, id, params["status"]) do
      json(conn, %{data: serialize(conn, Threads.get(project, id), Accounts.reviewer(account))})
    else
      {:error, :invalid_status} -> error(conn, 422, "Invalid status")
      _ -> error(conn, 404, "Not found")
    end
  end

  def delete_message(conn, %{"thread_id" => id, "message_id" => message_id}) do
    with account when not is_nil(account) <- conn.assigns.account,
         project when not is_nil(project) <- Accounts.demo_project(account),
         {:ok, result} <-
           Threads.delete_message(project, Accounts.reviewer(account), id, message_id) do
      json(conn, %{
        deleted_thread: result.deleted_thread,
        data:
          if(result.thread,
            do: serialize(conn, result.thread, Accounts.reviewer(account)),
            else: nil
          )
      })
    else
      _ -> error(conn, 404, "Comment not found or not yours to delete")
    end
  end

  # Demo storage uses its private project's canonical origin. The browser may use
  # another address for this same app (e.g. 127.0.0.1 instead of localhost).
  defp serialize(conn, thread, reviewer) do
    thread |> Threads.serialize(reviewer) |> Map.put(:page, request_origin(conn) <> "/")
  end

  defp request_origin(conn) do
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
    template = Accounts.demo_template()
    account = Accounts.current(get_session(conn, :account_token))

    cond do
      is_nil(template) ->
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
        conn |> assign(:account, account) |> assign(:template, template)
    end
  end

  defp registered?(nil), do: false
  defp registered?(account), do: not is_nil(account.email)

  defp error(conn, status, message),
    do: conn |> put_status(status) |> json(%{error: %{message: message}})
end
