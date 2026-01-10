defmodule Playground.Settings.AppSetting do
  @moduledoc """
  Key-value store for application settings.

  Provides a flexible way to store configuration that can be managed
  via a CRUD interface without requiring database migrations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:key],
    sortable: [:key, :value, :updated_at],
    default_order: %{order_by: [:key], order_directions: [:asc]},
    default_limit: 25
  }

  schema "app_settings" do
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(app_setting, attrs) do
    app_setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
