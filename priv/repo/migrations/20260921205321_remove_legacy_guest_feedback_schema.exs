defmodule Fluently.Repo.Migrations.RemoveLegacyGuestFeedbackSchema do
  use Ecto.Migration

  def up do
    if private_only?() do
      drop_if_exists table(:guest_review_sessions)
    end
  end

  def down do
    :ok
  end

  defp private_only?, do: Application.get_env(:fluently, :private_feedback_only, false)
end
