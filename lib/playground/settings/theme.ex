defmodule Playground.Settings.Theme do
  @moduledoc """
  Schema for customizable UI themes.

  Themes contain semantic color tokens that override Fluxon's default theme.
  Each theme is designated for either "light" or "dark" mode.
  System themes (is_system: true) are seeded defaults that cannot be deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_modes ~w(light dark)

  # These token keys match Fluxon's CSS variable names (with underscores instead of hyphens)
  # e.g., "background_base" becomes "--background-base" in CSS
  @token_keys ~w(
    primary
    primary_soft
    foreground
    foreground_soft
    foreground_softer
    foreground_softest
    foreground_primary
    background_base
    background_accent
    background_input
    surface
    overlay
    border_base
    danger
    success
    warning
    info
  )

  schema "themes" do
    field :name, :string
    field :slug, :string
    field :mode, :string
    field :is_system, :boolean, default: false
    field :tokens, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(theme, attrs) do
    theme
    |> cast(attrs, [:name, :slug, :mode, :is_system, :tokens])
    |> validate_required([:name, :slug, :mode, :tokens])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_tokens()
    |> unique_constraint(:slug)
  end

  defp validate_tokens(changeset) do
    case get_change(changeset, :tokens) do
      nil ->
        changeset

      tokens when is_map(tokens) ->
        missing_keys = @token_keys -- Map.keys(tokens)

        if missing_keys == [] do
          changeset
        else
          add_error(changeset, :tokens, "missing required keys: #{Enum.join(missing_keys, ", ")}")
        end

      _ ->
        add_error(changeset, :tokens, "must be a map")
    end
  end

  @doc """
  Returns the list of valid token keys.
  """
  def token_keys, do: @token_keys

  @doc """
  Returns the list of valid modes.
  """
  def valid_modes, do: @valid_modes
end
