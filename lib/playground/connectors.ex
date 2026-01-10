defmodule Playground.Connectors do
  @moduledoc """
  The Connectors context.

  Manages connector types (catalog) and organization connections to connectors.
  """

  import Ecto.Query, warn: false
  alias Playground.Repo

  alias Playground.Connectors.Connector
  alias Playground.Connectors.ConnectorOrganization
  alias Playground.Organizations

  ## Connector Catalog

  @doc """
  Lists all available connector types (Google Drive, Dropbox, etc.).

  ## Examples

      iex> list_connectors()
      [%Connector{}, ...]

  """
  def list_connectors do
    Repo.all(Connector)
  end

  @doc """
  Gets a connector by key.

  ## Examples

      iex> get_connector_by_key("google_drive")
      %Connector{}

      iex> get_connector_by_key("unknown")
      nil

  """
  def get_connector_by_key(key) do
    Repo.get_by(Connector, key: key)
  end

  @doc """
  Gets a single connector.

  Raises `Ecto.NoResultsError` if the Connector does not exist.

  ## Examples

      iex> get_connector!(123)
      %Connector{}

      iex> get_connector!(456)
      ** (Ecto.NoResultsError)

  """
  def get_connector!(id), do: Repo.get!(Connector, id)

  ## ConnectorOrganization (Org's Connection to a Connector)

  @doc """
  Lists all connector connections for a user's organization.

  Always scopes by the user's organization - never hardcode org IDs.

  ## Examples

      iex> list_organization_connectors(user)
      [%ConnectorOrganization{}, ...]

  """
  def list_organization_connectors(user) do
    org = Organizations.get_user_organization(user)

    from(co in ConnectorOrganization,
      where: co.organization_id == ^org.id,
      preload: [:connector, :user]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single connector organization.

  Raises `Ecto.NoResultsError` if the ConnectorOrganization does not exist.

  ## Examples

      iex> get_connector_organization!(123)
      %ConnectorOrganization{}

      iex> get_connector_organization!(456)
      ** (Ecto.NoResultsError)

  """
  def get_connector_organization!(id) do
    Repo.get!(ConnectorOrganization, id)
    |> Repo.preload([:connector, :user, :organization])
  end

  @doc """
  Gets a connector organization for a specific connector key and user's organization.

  ## Examples

      iex> get_organization_connector_by_key(user, "google_drive")
      %ConnectorOrganization{}

      iex> get_organization_connector_by_key(user, "unknown")
      nil

  """
  def get_organization_connector_by_key(user, connector_key) do
    org = Organizations.get_user_organization(user)
    connector = get_connector_by_key(connector_key)

    if org && connector do
      from(co in ConnectorOrganization,
        where: co.organization_id == ^org.id,
        where: co.connector_id == ^connector.id,
        preload: [:connector, :user]
      )
      |> Repo.one()
    end
  end

  @doc """
  Creates a connector organization.

  ## Examples

      iex> create_connector_organization(%{field: value})
      {:ok, %ConnectorOrganization{}}

      iex> create_connector_organization(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_connector_organization(attrs \\ %{}) do
    %ConnectorOrganization{}
    |> ConnectorOrganization.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a connector organization.

  ## Examples

      iex> update_connector_organization(connector_organization, %{field: new_value})
      {:ok, %ConnectorOrganization{}}

      iex> update_connector_organization(connector_organization, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_connector_organization(%ConnectorOrganization{} = connector_organization, attrs) do
    connector_organization
    |> ConnectorOrganization.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the metadata for a connector organization.

  ## Examples

      iex> update_connector_metadata(connector_organization, %{email: "user@example.com"})
      {:ok, %ConnectorOrganization{}}

  """
  def update_connector_metadata(%ConnectorOrganization{} = connector_organization, metadata) do
    connector_organization
    |> ConnectorOrganization.metadata_changeset(metadata)
    |> Repo.update()
  end

  @doc """
  Updates the status for a connector organization.

  ## Examples

      iex> update_connector_status(connector_organization, "active")
      {:ok, %ConnectorOrganization{}}

  """
  def update_connector_status(%ConnectorOrganization{} = connector_organization, status) do
    connector_organization
    |> ConnectorOrganization.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Updates the last_synced_at timestamp for a connector organization.

  ## Examples

      iex> update_connector_sync_time(connector_organization)
      {:ok, %ConnectorOrganization{}}

  """
  def update_connector_sync_time(%ConnectorOrganization{} = connector_organization) do
    connector_organization
    |> ConnectorOrganization.sync_changeset()
    |> Repo.update()
  end

  @doc """
  Updates the last_synced_at timestamp for a connector organization.
  Alias for update_connector_sync_time/1.
  """
  def update_last_synced(%ConnectorOrganization{} = connector_organization) do
    update_connector_sync_time(connector_organization)
  end

  @doc """
  Deletes a connector organization.

  ## Examples

      iex> delete_connector_organization(connector_organization)
      {:ok, %ConnectorOrganization{}}

      iex> delete_connector_organization(connector_organization)
      {:error, %Ecto.Changeset{}}

  """
  def delete_connector_organization(%ConnectorOrganization{} = connector_organization) do
    Repo.delete(connector_organization)
  end
end
