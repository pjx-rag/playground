defmodule Playground.Repo do
  use Ecto.Repo,
    otp_app: :playground,
    adapter: Ecto.Adapters.Postgres

  # Required by Authorizir for hierarchical authorization support
  use Dagex.Repo
end
