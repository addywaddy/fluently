defmodule Mix.Tasks.Fluently.Workspace do
  use Mix.Task
  @shortdoc "Provision a pilot workspace: mix fluently.workspace 'Studio name'"
  def run([name]) do
    Mix.Task.run("app.start")
    {:ok, workspace, key} = Fluently.Feedback.create_workspace(name)

    Mix.shell().info(
      "Workspace: #{workspace.name}\nSign in at /app/login with this owner key (save it securely):\n#{key}"
    )
  end

  def run(_), do: Mix.raise("Usage: mix fluently.workspace 'Studio name'")
end
