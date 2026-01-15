alias Playground.Repo
alias Playground.Settings.AppSetting

# Seed default app settings with idempotent upserts

app_settings = [
  %{
    key: "ai_default_model",
    value: "mistralai/devstral-2512:free"
  },
  %{
    key: "ai_temperature",
    value: "0.7"
  },
  %{
    key: "ai_max_tokens",
    value: "4096"
  },
  %{
    key: "ai_top_p",
    value: "1.0"
  },
  %{
    key: "ai_frequency_penalty",
    value: "0.0"
  },
  %{
    key: "ai_presence_penalty",
    value: "0.0"
  },
  %{
    key: "pdf_analysis_model",
    value: "mistralai/mistral-large-2512"
  },
  %{
    key: "embedding_model",
    value: "text-embedding-3-small"
  },
  %{
    key: "embedding_dimensions",
    value: "1536"
  },
  %{
    key: "rag_mode",
    value: "agentic_rag"
  },
  %{
    key: "rag_agent_model",
    value: "anthropic/claude-3.5-haiku"
  },
  %{
    key: "rag_debug_mode",
    value: "false"
  },
  %{
    key: "api_log_truncate_length",
    value: "2000"
  }
]

Enum.each(app_settings, fn setting_attrs ->
  %AppSetting{}
  |> AppSetting.changeset(setting_attrs)
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :key)
end)

IO.puts("✓ Seeded #{length(app_settings)} app settings")
