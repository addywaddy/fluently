defmodule FluentlyWeb.ManageController do
  use FluentlyWeb, :controller
  import Phoenix.Component, only: [to_form: 1, to_form: 2]
  alias Fluently.Feedback
  plug :secure_page
  plug :require_owner when action not in [:login, :authenticate]

  def login(conn, _), do: render(conn, :login, form: to_form(%{}), error: nil)

  def authenticate(conn, %{"key" => key}) when is_binary(key) do
    if Fluently.RateLimit.allow?({:owner_login, conn.remote_ip}, 10) do
      case Feedback.authenticate_owner(key) do
        nil ->
          conn
          |> put_status(401)
          |> render(:login, form: to_form(%{}), error: "Invalid owner key.")

        workspace ->
          conn
          |> configure_session(renew: true)
          |> clear_session()
          |> put_session(
            :owner,
            Phoenix.Token.sign(FluentlyWeb.Endpoint, "owner-v1", workspace.id)
          )
          |> redirect(to: ~p"/app")
      end
    else
      conn
      |> put_status(429)
      |> render(:login, form: to_form(%{}), error: "Too many attempts. Try again in a minute.")
    end
  end

  def authenticate(conn, _),
    do:
      conn
      |> put_status(400)
      |> render(:login, form: to_form(%{}), error: "Enter your owner key.")

  def logout(conn, _) do
    Fluently.Accounts.logout(Fluently.Accounts.current(get_session(conn, :account_token)))
    conn |> configure_session(drop: true) |> redirect(to: ~p"/")
  end

  def index(conn, _),
    do:
      render(conn, :index,
        projects: Feedback.projects(conn.assigns.workspace),
        form: to_form(%{}, as: :project),
        error: nil
      )

  def create(conn, %{"project" => attrs}) do
    case Feedback.create_project(conn.assigns.workspace, attrs) do
      {:ok, p, credentials} ->
        redirect_with_credentials(conn, p, credentials)

      {:error, _} ->
        conn
        |> put_status(422)
        |> render(:index,
          projects: Feedback.projects(conn.assigns.workspace),
          form: to_form(attrs, as: :project),
          error:
            "Enter a name and an exact HTTPS origin, e.g. https://staging.example.com. HTTP is allowed for localhost."
        )
    end
  end

  def show(conn, %{"id" => id}) do
    case Feedback.project(conn.assigns.workspace, id) do
      nil ->
        send_resp(conn, 404, "Not found")

      p ->
        credentials =
          case Phoenix.Token.decrypt(
                 FluentlyWeb.Endpoint,
                 "issued-project-keys",
                 get_session(conn, :issued_keys) || "",
                 max_age: 300
               ) do
            {:ok, %{project: ^id, credentials: credentials}} -> credentials
            _ -> nil
          end

        conn |> delete_session(:issued_keys) |> show_page(p, credentials)
    end
  end

  def rotate(conn, %{"id" => id}) do
    case Feedback.rotate_project(conn.assigns.workspace, id) do
      {:ok, p, credentials} -> redirect_with_credentials(conn, p, credentials)
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def delete(conn, %{"id" => id, "confirm" => "delete"}) do
    case Feedback.delete_project(conn.assigns.workspace, id) do
      {:ok, _} -> redirect(conn, to: ~p"/app")
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def delete(conn, _), do: send_resp(conn, 422, "Type delete to confirm.")

  def delete_thread(conn, %{"id" => id, "thread_id" => tid}) do
    with p when not is_nil(p) <- Feedback.project(conn.assigns.workspace, id),
         {:ok, _} <- Fluently.Threads.delete(p, tid) do
      redirect(conn, to: ~p"/app/projects/#{id}")
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp redirect_with_credentials(conn, p, credentials) do
    sealed =
      Phoenix.Token.encrypt(FluentlyWeb.Endpoint, "issued-project-keys", %{
        project: p.id,
        credentials: credentials
      })

    conn |> put_session(:issued_keys, sealed) |> redirect(to: ~p"/app/projects/#{p.id}")
  end

  defp show_page(conn, p, credentials) do
    render(conn, :show,
      project: p,
      credentials: credentials,
      service_url: FluentlyWeb.Endpoint.url(),
      threads: Fluently.Threads.list(p, %{}),
      form: to_form(%{})
    )
  end

  defp secure_page(conn, _) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
  end

  defp require_owner(conn, _) do
    account = Fluently.Accounts.current(get_session(conn, :account_token))

    if account && account.email do
      assign(conn, :workspace, Feedback.workspace(account.workspace_id))
    else
      require_pilot_owner(conn)
    end
  end

  defp require_pilot_owner(conn) do
    with {:ok, id} <-
           Phoenix.Token.verify(FluentlyWeb.Endpoint, "owner-v1", get_session(conn, :owner) || "",
             max_age: 43_200
           ),
         workspace when not is_nil(workspace) <- Feedback.workspace(id) do
      assign(conn, :workspace, workspace)
    else
      _ -> conn |> redirect(to: ~p"/app/login") |> halt()
    end
  end
end
