defmodule Playground.Files.Queries do
  @moduledoc """
  Query operations for files.

  Used by:
  - AdminFilesLive.Index
  - FilesLive.Index
  - ConnectorOrganizationsLive
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.Organizations

  @doc """
  Lists all files for a connector organization, excluding deleted files by default.

  ## Examples

      iex> list_for_connector(connector_organization_id)
      [%File{}, ...]

      iex> list_for_connector(connector_organization_id, include_deleted: true)
      [%File{}, ...]

  """
  def list_for_connector(connector_organization_id, opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    query =
      from(f in File,
        where: f.connector_organization_id == ^connector_organization_id,
        order_by: [desc: f.inserted_at]
      )

    query =
      if include_deleted do
        query
      else
        from(f in query, where: f.sync_status != "deleted")
      end

    Repo.all(query)
  end

  @doc """
  Lists synced files for a user's organization connectors.

  Always scopes by the user's organization.

  ## Examples

      iex> list_synced_for_user(user)
      [%File{}, ...]

  """
  def list_synced_for_user(user) do
    org = Organizations.get_user_organization(user)
    connector_org_ids = get_connector_org_ids(org.id)

    from(f in File,
      where: f.connector_organization_id in ^connector_org_ids,
      where: f.sync_status == "synced",
      preload: [connector_organization: :connector]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single file with organization verification.

  Raises `Ecto.NoResultsError` if the File does not exist or user doesn't have access.

  ## Examples

      iex> get_for_user!(123, user)
      %File{}

      iex> get_for_user!(456, user)
      ** (Ecto.NoResultsError)

  """
  def get_for_user!(id, user) do
    org = Organizations.get_user_organization(user)

    from(f in File,
      join: co in assoc(f, :connector_organization),
      where: f.id == ^id and co.organization_id == ^org.id,
      preload: [connector_organization: :connector]
    )
    |> Repo.one!()
  end

  @doc """
  Gets a file by provider file ID and connector organization.

  ## Examples

      iex> get_by_provider_id(connector_org_id, "abc123")
      %File{}

      iex> get_by_provider_id(connector_org_id, "unknown")
      nil

  """
  def get_by_provider_id(connector_organization_id, provider_file_id) do
    Repo.get_by(File,
      connector_organization_id: connector_organization_id,
      provider_file_id: provider_file_id
    )
  end

  @doc """
  Gets the count of files by sync status for a connector organization.

  ## Examples

      iex> count_by_status(connector_org_id)
      %{"synced" => 10, "unsynced" => 5}

  """
  def count_by_status(connector_organization_id) do
    from(f in File,
      where: f.connector_organization_id == ^connector_organization_id,
      where: f.sync_status != "deleted",
      group_by: f.sync_status,
      select: {f.sync_status, count(f.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Private helper to get connector org IDs for an organization
  defp get_connector_org_ids(organization_id) do
    from(co in Playground.Connectors.ConnectorOrganization,
      where: co.organization_id == ^organization_id,
      select: co.id
    )
    |> Repo.all()
  end
end
