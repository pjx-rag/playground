defmodule Playground.Release do
  @moduledoc """
  Release tasks for production deployments.

  Used by the release migration script.
  """

  @app :playground

  @doc """
  Run database migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rollback the last migration.
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Run database seeds after migrations.
  """
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          # Run seeds
          run_seeds()
        end)
    end
  end

  @doc """
  Run migrations and then seeds.
  """
  def setup do
    migrate()
    seed()
  end

  defp run_seeds do
    seeds_path = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seeds_path) do
      Code.eval_file(seeds_path)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
