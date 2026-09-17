defmodule Fluently.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :fluently

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def create_workspace(name) do
    load_app()

    {:ok, {:ok, workspace, key}, _} =
      Ecto.Migrator.with_repo(Fluently.Repo, fn _ -> Fluently.Feedback.create_workspace(name) end)

    IO.puts("Workspace: #{workspace.name}\nOwner key (save securely): #{key}")
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
