defmodule FluentlyWeb.AccountController do
  use FluentlyWeb, :controller
  import Phoenix.Component, only: [to_form: 2]
  alias Fluently.{Accounts, RateLimit}
  plug :secure_page

  def signup(conn, _), do: render_form(conn, :signup)
  def login(conn, _), do: render_form(conn, :login)

  def register(conn, %{"account" => attrs}) do
    if RateLimit.allow?({:account_auth, conn.remote_ip}, 5) do
      case Accounts.register(Accounts.current(get_session(conn, :account_token)), attrs) do
        {:ok, {_account, token}} ->
          sign_in(conn, token)

        _ ->
          conn
          |> put_status(422)
          |> render_form(
            :signup,
            "Could not create your account. Use a name, valid email and a password of 15–128 characters. If you already have an account, sign in."
          )
      end
    else
      conn |> put_status(429) |> render_form(:signup, "Too many attempts. Try again in a minute.")
    end
  end

  def register(conn, _),
    do: conn |> put_status(422) |> render_form(:signup, "Complete all fields.")

  def authenticate(conn, %{"account" => attrs}) do
    if RateLimit.allow?({:account_auth, conn.remote_ip}, 5) do
      case Accounts.login(attrs["email"], attrs["password"]) do
        {:ok, _account, token} -> sign_in(conn, token)
        _ -> conn |> put_status(401) |> render_form(:login, "Invalid email or password.")
      end
    else
      conn |> put_status(429) |> render_form(:login, "Too many attempts. Try again in a minute.")
    end
  end

  def authenticate(conn, _),
    do: conn |> put_status(401) |> render_form(:login, "Enter your email and password.")

  defp sign_in(conn, token) do
    review_connect = get_session(conn, :review_connect)
    invitation_token = get_session(conn, :invitation_token)
    guest_token = get_session(conn, :guest_review_token) || get_session(conn, :account_token)

    guest_token =
      if Fluently.GuestReviews.current(Accounts.public_project(), guest_token), do: guest_token

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:account_token, token)
    |> put_session(:guest_review_token, guest_token)
    |> put_session(:review_connect, review_connect)
    |> put_session(:invitation_token, invitation_token)
    |> redirect(
      to:
        cond do
          review_connect -> ~p"/review/connect"
          invitation_token -> ~p"/invitations/#{invitation_token}"
          true -> ~p"/app"
        end
    )
  end

  defp render_form(conn, mode, error \\ nil),
    do:
      render(conn, :auth,
        mode: mode,
        error: error,
        form: to_form(%{}, as: :account),
        page_title: if(mode == :signup, do: "Sign up · Fluently", else: "Log in · Fluently")
      )

  defp secure_page(conn, _),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
end
