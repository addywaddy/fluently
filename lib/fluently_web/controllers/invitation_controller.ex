defmodule FluentlyWeb.InvitationController do
  use FluentlyWeb, :controller
  import Phoenix.Component, only: [to_form: 1]

  alias Fluently.{Accounts, Invitations}

  plug :secure_page

  def show(conn, %{"token" => token}) do
    case Accounts.current(get_session(conn, :account_token)) do
      %{email: email} = account when is_binary(email) ->
        render_for_account(conn, token, account)

      _ ->
        conn
        |> put_session(:invitation_token, token)
        |> redirect(to: ~p"/login")
    end
  end

  def accept(conn, %{"token" => token}) do
    case Accounts.current(get_session(conn, :account_token)) do
      %{user_id: user_id} when is_binary(user_id) ->
        case Invitations.accept(token, user_id) do
          {:ok, _} ->
            conn
            |> delete_session(:invitation_token)
            |> put_flash(:info, "Invitation accepted. You can now review the assigned project.")
            |> redirect(to: ~p"/app")

          _ ->
            conn
            |> put_status(422)
            |> render(:show,
              token: token,
              account: Accounts.current(get_session(conn, :account_token)),
              form: to_form(%{}),
              error:
                "This invitation is invalid, expired, revoked, or belongs to another email address."
            )
        end

      _ ->
        conn |> put_session(:invitation_token, token) |> redirect(to: ~p"/login")
    end
  end

  defp render_for_account(conn, token, %{email: email} = account) do
    invitation =
      Fluently.Repo.get_by(Fluently.Accounts.Invitation,
        token_hash: Fluently.Feedback.hash(token)
      )

    if invitation && String.downcase(invitation.email) == String.downcase(email) do
      render(conn, :show, token: token, account: account, form: to_form(%{}), error: nil)
    else
      conn
      |> put_status(422)
      |> render(:show,
        token: token,
        account: account,
        form: to_form(%{}),
        error:
          "This invitation is invalid, expired, revoked, or belongs to another email address."
      )
    end
  end

  defp secure_page(conn, _) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
  end
end
