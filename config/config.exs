# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Oban configuration for background jobs
config :playground, Oban,
  name: Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.PG,
  queues: [
    default: 10,
    mailers: 5,
    backups: 1,
    ai_chat: 5
  ],
  repo: Playground.Repo,
  plugins: [
    Oban.Met,
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ],
  crontab: [
    # Database backup daily at 3:00 AM EST (8:00 AM UTC)
    {"0 8 * * *", Playground.Workers.DatabaseBackupWorker, args: %{}},
    # Clean up old API request logs daily at 4:00 AM UTC
    {"0 4 * * *", Playground.Workers.APIRequestLogCleanupWorker, args: %{}}
  ]

config :playground,
  ecto_repos: [Playground.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :playground, PlaygroundWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PlaygroundWeb.ErrorHTML, json: PlaygroundWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Playground.PubSub,
  live_view: [signing_salt: "JArKbTeZ"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :playground, Playground.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  playground: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --loader:.js=jsx --loader:.jsx=jsx),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :logger,
  backends: [:console],
  level: :info

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Error Tracker configuration (basic config - enabled flag moved to runtime.exs)
config :error_tracker,
  repo: Playground.Repo,
  otp_app: :playground

# Phoenix Analytics configuration
config :phoenix_analytics,
  repo: Playground.Repo,
  app_domain: "localhost"

# Flop configuration for pagination/filtering
config :flop,
  repo: Playground.Repo,
  default_limit: 25,
  max_limit: 100

# API Request Logger configuration
config :playground, Playground.APIRequestLogger,
  persist_to_db: true,
  retention_days: 30,
  buffer_size: 1000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
