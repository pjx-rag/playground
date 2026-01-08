defmodule Playground.MixProject do
  use Mix.Project

  def project do
    [
      app: :playground,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Playground.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp releases do
    [
      playground: [
        overlays: ["rel/overlays"]
      ]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Phoenix core
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:tidewave, "~> 0.5", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},

      # Authentication & Authorization
      {:bcrypt_elixir, "~> 3.0"},
      {:authorizir, "~> 1.0"},
      {:bodyguard, "~> 2.4"},

      # UI Components
      {:fluxon, "~> 2.3", repo: :fluxon},
      {:flop, "~> 0.26"},
      {:flop_phoenix, "~> 0.23"},
      {:live_select, "~> 1.4"},

      # Background Jobs
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.10"},

      # HTTP Client
      {:req, "~> 0.5"},
      {:req_llm, "~> 1.2"},
      {:finch, "~> 0.13"},

      # Markdown Rendering
      {:mdex, "~> 0.2"},

      # Caching
      {:cachex, "~> 4.0"},

      # Email
      {:swoosh, "~> 1.20"},
      {:resend, "~> 0.4.1"},

      # File Uploads (S3/Tigris)
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.15"},
      {:sweet_xml, "~> 0.7"},

      # Monitoring & Error Tracking
      {:error_tracker, "~> 0.7.1"},

      # Analytics
      {:phoenix_analytics, "~> 0.4"},

      # Utilities
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.10"},

      # State Machines
      {:machinery, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "cmd --cd assets npm install --legacy-peer-deps",
        "esbuild.install --if-missing"
      ],
      "assets.build": [
        "esbuild playground",
        "cmd --cd assets npm run build"
      ],
      "assets.deploy": [
        "esbuild playground --minify",
        "cmd --cd assets npm run deploy",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
