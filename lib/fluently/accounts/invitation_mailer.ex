defmodule Fluently.Accounts.InvitationMailer do
  import Swoosh.Email

  alias Fluently.Mailer

  def invite(invitation, token) do
    url = FluentlyWeb.Endpoint.url() <> "/invitations/" <> URI.encode(token)

    new()
    |> to(invitation.email)
    |> from(Mailer.sender())
    |> subject("You’ve been invited to review with Fluently")
    |> text_body(
      "You have been invited to review a Fluently project. Sign in or create your account, then open this link to accept: #{url}"
    )
  end
end
