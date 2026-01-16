defmodule Playground.Services.Connectors.ConnectorOrganization do
  @moduledoc """
  An organization's connection to a connector type.

  This is the join table representing "a connector" in code.
  E.g., PJX organization's connection to Google Drive.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending_auth awaiting_sync syncing synced disconnected)

  schema "connector_organizations" do
    belongs_to :organization, Playground.Accounts.Organizations.Organization
    belongs_to :connector, Playground.Services.Connectors.Connector
    belongs_to :user, Playground.Accounts.User

    field :status, :string, default: "pending_auth"
    field :metadata, :map, default: %{}
    field :last_synced_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(connector_organization, attrs) do
    connector_organization
    |> cast(attrs, [:organization_id, :connector_id, :user_id, :status, :metadata, :last_synced_at])
    |> validate_required([:organization_id, :connector_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:connector_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:organization_id, :connector_id])
  end

  @doc false
  def metadata_changeset(connector_organization, metadata) do
    connector_organization
    |> cast(%{metadata: metadata}, [:metadata])
  end

  @doc false
  def status_changeset(connector_organization, status) do
    connector_organization
    |> cast(%{status: status}, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc false
  def sync_changeset(connector_organization) do
    connector_organization
    |> cast(%{last_synced_at: DateTime.utc_now()}, [:last_synced_at])
  end
end
