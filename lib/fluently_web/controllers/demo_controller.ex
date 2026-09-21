defmodule FluentlyWeb.DemoController do
  use FluentlyWeb, :controller
  alias Fluently.{Accounts, Feedback, GuestReviews, ProjectAccess, Threads, RateLimit, Snapshots}
  plug :boundary
  plug :thread_boundary

  def index(conn, %{"view" => view}) when view not in [nil, "all", "mine"],
    do: error(conn, 422, "view must be all or mine")

  def index(conn, params) do
    threads =
      Threads.list(
        conn.assigns.project,
        Map.put(params, "page", conn.assigns.project.origin <> "/"),
        list_scope(conn, params)
      )

    json(conn, %{
      data: Enum.map(threads, &serialize(conn, &1)),
      registered: not is_nil(conn.assigns.account),
      identity: identity_label(conn),
      next_offset:
        if(length(threads) == 100, do: Threads.offset(params["offset"]) + 100, else: nil)
    })
  end

  def create(conn, params) do
    project = conn.assigns.project
    params = Map.put(params, "page", project.origin <> "/")

    result =
      if conn.assigns.member do
        with {:ok, identity} <- ProjectAccess.reviewer(conn.assigns.workspace, project),
             {:ok, thread} <- Threads.create(project, identity, params),
             do: {:ok, %{thread: thread, identity: identity, token: nil}}
      else
        GuestReviews.create_comment(project, conn.assigns.guest_token, params)
      end

    case result do
      {:ok, %{thread: thread, identity: identity, token: token}} ->
        conn =
          if token,
            do: conn |> put_session(:guest_review_token, token) |> assign(:guest, identity),
            else: conn

        conn
        |> assign(:identity, identity)
        |> put_status(201)
        |> json(%{data: serialize(conn, thread, identity)})

      _ ->
        error(conn, 422, "Could not save your comment. Check the text or reload and try again.")
    end
  end

  def snapshot(conn, %{"thread_id" => id}) do
    case Snapshots.get(conn.assigns.project, id) do
      nil -> error(conn, 404, "Snapshot not found")
      snapshot -> json(conn, %{data: Snapshots.serialize(snapshot)})
    end
  end

  def attach_snapshot(conn, %{"thread_id" => id} = params) do
    thread = Threads.get(conn.assigns.project, id)
    author = Enum.find(identities(conn), &(&1.id == thread.reviewer_id))

    case Snapshots.attach(conn.assigns.project, author, id, params["data_url"]) do
      {:ok, _} ->
        json(conn, %{data: serialize(conn, Threads.get(conn.assigns.project, id))})

      {:error, :invalid_image} ->
        error(conn, 422, "Use a PNG up to 200 KiB and 1200 × 1200 pixels")

      _ ->
        error(conn, 404, "Comment not found or not yours")
    end
  end

  def reply(conn, %{"thread_id" => id} = params) do
    with {:ok, identity} <- actor(conn),
         {:ok, _} <- Threads.reply(conn.assigns.project, identity, id, params["body"]) do
      json(conn, %{data: serialize(conn, Threads.get(conn.assigns.project, id), identity)})
    else
      {:error, %Ecto.Changeset{}} -> error(conn, 422, "Write a reply of 1–4000 characters.")
      _ -> error(conn, 404, "Not found")
    end
  end

  def update(conn, %{"thread_id" => id} = params) do
    case Threads.status(conn.assigns.project, id, params["status"]) do
      {:ok, _} -> json(conn, %{data: serialize(conn, Threads.get(conn.assigns.project, id))})
      {:error, :invalid_status} -> error(conn, 422, "Invalid status")
      _ -> error(conn, 404, "Not found")
    end
  end

  def delete_message(conn, %{"thread_id" => id, "message_id" => mid}) do
    thread = Threads.get(conn.assigns.project, id)

    with message when not is_nil(message) <- Enum.find(thread.messages, &(&1.id == mid)),
         author when not is_nil(author) <- author_for_message(conn, message),
         {:ok, result} <- Threads.delete_message(conn.assigns.project, author, id, mid) do
      json(conn, %{
        deleted_thread: result.deleted_thread,
        data: if(result.thread, do: serialize(conn, result.thread), else: nil)
      })
    else
      _ -> error(conn, 404, "Comment not found or not yours to delete")
    end
  end

  defp serialize(conn, thread, extra \\ nil) do
    ids = Enum.map(Enum.reject([extra | identities(conn)], &is_nil/1), &identity_key/1)

    thread
    |> Threads.serialize()
    |> Map.put(:page, request_origin(conn) <> "/")
    |> Map.update!(:messages, fn messages ->
      Enum.map(messages, &Map.put(&1, :can_delete, identity_key(&1.author) in ids))
    end)
  end

  defp identities(conn), do: Enum.reject([conn.assigns.guest, conn.assigns.identity], &is_nil/1)

  defp identity_key(%{user_id: user_id}) when is_binary(user_id), do: user_id
  defp identity_key(%{id: id}), do: id
  defp identity_key(_), do: nil

  defp author_for_message(conn, message) do
    Enum.find(identities(conn), fn identity ->
      identity_key(identity) in [message.reviewer_id, message.author_user_id]
    end)
  end

  defp list_scope(conn, %{"view" => "mine"}) do
    case conn.assigns.identity do
      %{account_member: true, user_id: user_id} -> {:user, user_id}
      %{id: id} -> id
      _ -> :none
    end
  end

  defp list_scope(conn, _), do: scope(conn)

  defp scope(%{assigns: %{member: true}}), do: :all
  defp scope(%{assigns: %{guest: %{id: id}}}), do: id
  defp scope(_), do: :none

  defp actor(%{assigns: %{member: true}} = conn),
    do: ProjectAccess.reviewer(conn.assigns.workspace, conn.assigns.project)

  defp actor(%{assigns: %{guest: guest}}) when not is_nil(guest), do: {:ok, guest}
  defp actor(_), do: {:error, :not_found}

  defp identity_label(conn) do
    if conn.assigns.member,
      do: %{
        kind: if(conn.assigns.account, do: "account", else: "admin"),
        name: (conn.assigns.account && conn.assigns.account.name) || "Project owner"
      },
      else: %{kind: "guest", name: "Guest"}
  end

  defp request_origin(conn) do
    Application.get_env(:fluently, :canonical_feedback_origin) ||
      conn
      |> request_url()
      |> URI.parse()
      |> Map.merge(%{path: nil, query: nil, fragment: nil})
      |> URI.to_string()
  end

  defp boundary(conn, _) do
    conn = put_resp_header(conn, "cache-control", "no-store")
    project = Accounts.public_project()

    account =
      case Accounts.current(get_session(conn, :account_token)) do
        %{email: email} = account when not is_nil(email) -> account
        _ -> nil
      end

    workspace = workspace(conn, account)

    member =
      not is_nil(project) && not is_nil(workspace) &&
        not is_nil(ProjectAccess.project(workspace, project.id))

    token = get_session(conn, :guest_review_token) || get_session(conn, :account_token)

    guest =
      if Accounts.private_feedback_only?() or is_nil(project),
        do: nil,
        else: GuestReviews.current(project, token)

    cond do
      not Accounts.demo_enabled?() or is_nil(project) ->
        conn |> error(404, "Feedback unavailable") |> halt()

      Accounts.private_feedback_only?() and not member ->
        conn |> error(403, "Feedback is available to invited project members") |> halt()

      get_req_header(conn, "origin") not in [[], [request_origin(conn)]] ->
        conn |> error(403, "Origin not allowed") |> halt()

      not RateLimit.allow?(
        {:demo_ip, conn.remote_ip, conn.method == "GET"},
        if(conn.method == "GET", do: 180, else: 30)
      ) ->
        conn |> error(429, "Too many requests. Try again in a minute.") |> halt()

      guest &&
          not RateLimit.allow?(
            {:guest_review, guest.id, conn.method == "GET"},
            if(conn.method == "GET", do: 180, else: 40)
          ) ->
        conn |> error(429, "Too many requests. Try again in a minute.") |> halt()

      true ->
        conn = if guest, do: put_session(conn, :guest_review_token, token), else: conn

        conn
        |> assign(:account, account)
        |> assign(:workspace, workspace)
        |> assign(:member, member)
        |> assign(:project, project)
        |> assign(:guest, guest)
        |> assign(:guest_token, if(guest, do: token, else: nil))
        |> assign(
          :identity,
          if(member, do: ProjectAccess.existing_reviewer(workspace, project), else: guest)
        )
    end
  end

  defp workspace(_conn, account) when not is_nil(account),
    do: Feedback.workspace(account.workspace_id)

  defp workspace(conn, _) do
    with {:ok, id} <-
           Phoenix.Token.verify(FluentlyWeb.Endpoint, "owner-v1", get_session(conn, :owner) || "",
             max_age: 43_200
           ),
         do: Feedback.workspace(id),
         else: (_ -> nil)
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
