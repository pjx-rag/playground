defmodule Playground.Settings.AppSettingsManager do
  @moduledoc """
  App settings management operations (key-value store).

  Used by:
  - AdminSettingsLive.AppSettings
  - AI context (for model defaults)
  - RAG embedding configuration
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Settings.AppSetting

  @doc """
  Returns all app settings.
  """
  def list_all do
    Repo.all(from s in AppSetting, order_by: [asc: s.key])
  end

  @doc """
  Gets a single app setting by ID.
  """
  def get!(id), do: Repo.get!(AppSetting, id)

  @doc """
  Gets a single app setting by key.
  Returns nil if not found.
  """
  def get_by_key(key) do
    Repo.get_by(AppSetting, key: key)
  end

  @doc """
  Gets the value for an app setting by key.
  Returns the default if not found.
  """
  def get_value(key, default \\ nil) do
    case get_by_key(key) do
      nil -> default
      setting -> setting.value
    end
  end

  @doc """
  Creates an app setting.
  """
  def create(attrs \\ %{}) do
    %AppSetting{}
    |> AppSetting.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an app setting.
  """
  def update(%AppSetting{} = app_setting, attrs) do
    app_setting
    |> AppSetting.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Sets an app setting value by key (upsert).
  Creates the setting if it doesn't exist, updates if it does.
  """
  def set(key, value) do
    case get_by_key(key) do
      nil ->
        create(%{key: key, value: value})

      setting ->
        __MODULE__.update(setting, %{value: value})
    end
  end

  @doc """
  Deletes an app setting.
  """
  def delete(%AppSetting{} = app_setting) do
    Repo.delete(app_setting)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking app setting changes.
  """
  def change(%AppSetting{} = app_setting, attrs \\ %{}) do
    AppSetting.changeset(app_setting, attrs)
  end

  @doc """
  Seeds the default app settings if they don't exist.
  """
  def seed_defaults do
    default_app_settings()
    |> Enum.each(fn {key, value} ->
      case get_by_key(key) do
        nil -> create(%{key: key, value: value})
        _existing -> :ok
      end
    end)

    :ok
  end

  defp default_app_settings do
    [
      {"ai_default_model", "mistralai/devstral-2512:free"},
      {"ai_temperature", "0.7"},
      {"ai_max_tokens", "4096"},
      {"ai_top_p", "1.0"},
      {"ai_frequency_penalty", "0.0"},
      {"ai_presence_penalty", "0.0"},
      {"pdf_analysis_model", "mistralai/mistral-large-2512"},
      {"embedding_model", "text-embedding-3-small"},
      {"embedding_dimensions", "1536"}
    ]
  end
end
