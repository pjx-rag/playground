defmodule Playground.Connectors.Connector do
  @moduledoc """
  Catalog of available connector types (Google Drive, Dropbox, etc.).

  This is NOT a user's connection - see ConnectorOrganization for that.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "connectors" do
    field :key, :string
    field :name, :string
    field :icon, :string

    has_many :connector_organizations, Playground.Connectors.ConnectorOrganization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(connector, attrs) do
    connector
    |> cast(attrs, [:key, :name, :icon])
    |> validate_required([:key, :name])
    |> validate_length(:key, min: 1, max: 255)
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:key)
  end
end
