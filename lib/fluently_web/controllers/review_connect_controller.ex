defmodule FluentlyWeb.ReviewConnectController do
  use FluentlyWeb, :controller
  import Phoenix.Component, only: [to_form: 1]
  alias Fluently.{Accounts, AccountReviews, Feedback, RateLimit}
  plug :secure_page

  def show(conn, %{"project" => id} = params) do
    project = Feedback.project(id)

    if project && AccountReviews.return_url?(project, params["return_to"]) &&
         AccountReviews.valid_nonce?(params["state"]) &&
         AccountReviews.valid_nonce?(params["challenge"]) do
      pending =
        Map.take(params, ["project", "return_to", "state", "challenge"])
        |> Map.put("created_at", System.system_time(:second))

      conn |> put_session(:review_connect, pending) |> show(%{})
    else
      conn
      |> put_status(400)
      |> text("Invalid review connection. Reopen the project’s review link.")
    end
  end

  def show(conn, _) do
    with {:ok, pending, project} <- pending(conn) do
      account = Accounts.current(get_session(conn, :account_token))

      if account && account.email do
        render(conn, :confirm,
          project: project,
          account: account,
          member: AccountReviews.member?(account, project),
          form: to_form(%{}),
          state: pending["state"],
          page_title: "Continue with Fluently"
        )
      else
        redirect(conn, to: ~p"/login")
      end
    else
      _ ->
        conn
        |> put_status(400)
        |> text("Review connection expired. Start again from the website.")
    end
  end

  def create(conn, params) do
    with true <- RateLimit.allow?({:account_review_connect, conn.remote_ip}, 20),
         {:ok, pending, project} <- pending(conn),
         true <- params["state"] == pending["state"] do
      account = Accounts.current(get_session(conn, :account_token))

      result =
        if params["action"] == "connect",
          do: AccountReviews.issue(project, account, pending["challenge"])

      fields =
        case result do
          {:ok, code} -> %{"fluently_code" => code, "fluently_state" => pending["state"]}
          _ -> %{"fluently_result" => "guest", "fluently_state" => pending["state"]}
        end

      uri = URI.parse(pending["return_to"])
      fragment = URI.decode_query(uri.fragment || "") |> Map.merge(fields) |> URI.encode_query()

      conn
      |> delete_session(:review_connect)
      |> redirect(external: URI.to_string(%{uri | fragment: fragment}))
    else
      _ ->
        conn
        |> put_status(400)
        |> text("Review connection expired. Start again from the website.")
    end
  end

  defp pending(conn) do
    with %{"created_at" => created, "project" => id} = pending <-
           get_session(conn, :review_connect),
         true <- (System.system_time(:second) - created) in 0..600,
         project when not is_nil(project) <- Feedback.project(id),
         true <- AccountReviews.return_url?(project, pending["return_to"]) do
      {:ok, pending, project}
    else
      _ -> {:error, :invalid}
    end
  end

  defp secure_page(conn, _),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
end
