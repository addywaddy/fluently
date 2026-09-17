defmodule Fluently.Mailer do
  use Swoosh.Mailer, otp_app: :fluently
  @doc "Configured sender shared by transactional emails."
  def sender, do: Application.fetch_env!(:fluently, :mail_from)
end
