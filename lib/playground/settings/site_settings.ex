defmodule Playground.Settings.SiteSettings do
  @moduledoc """
  Singleton schema for site-wide settings.

  This table should only ever have one row. Use `Settings.get_site_settings/0`
  to fetch or create the singleton record.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playground.Settings.Theme

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "site_settings" do
    field :logo_url, :string
    field :ai_rate_limit_per_minute, :integer, default: 20
    field :ai_rate_limit_per_hour, :integer, default: 100
    field :ai_rate_limit_per_day, :integer, default: 500

    belongs_to :light_theme, Theme
    belongs_to :dark_theme, Theme

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(site_settings, attrs) do
    site_settings
    |> cast(attrs, [
      :logo_url,
      :light_theme_id,
      :dark_theme_id,
      :ai_rate_limit_per_minute,
      :ai_rate_limit_per_hour,
      :ai_rate_limit_per_day
    ])
    |> validate_url(:logo_url)
    |> validate_number(:ai_rate_limit_per_minute, greater_than: 0)
    |> validate_number(:ai_rate_limit_per_hour, greater_than: 0)
    |> validate_number(:ai_rate_limit_per_day, greater_than: 0)
    |> foreign_key_constraint(:light_theme_id)
    |> foreign_key_constraint(:dark_theme_id)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case value do
        nil -> []
        "" -> []
        url when is_binary(url) ->
          if String.starts_with?(url, ["http://", "https://", "/"]) do
            []
          else
            [{field, "must be a valid URL starting with http://, https://, or /"}]
          end
        _ -> [{field, "must be a string"}]
      end
    end)
  end
end
