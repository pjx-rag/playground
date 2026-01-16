defmodule Playground.Accounts.Organizations do
  @moduledoc """
  Organizations sub-context within Accounts.

  Manages organizations and their user memberships. All users belong to exactly one organization.
  Currently hardcoded to "PJX" organization for single-tenant UI with multi-tenant backend.

  Organizations provide tenant boundaries for multi-tenancy within the Accounts context.
  """

  import Ecto.Query, warn: false
  alias Playground.Repo

  alias Playground.Accounts.Organizations.{Organization, OrganizationUser}

  @doc """
  Gets a single organization.

  Raises `Ecto.NoResultsError` if the Organization does not exist.

  ## Examples

      iex> get_organization!(123)
      %Organization{}

      iex> get_organization!(456)
      ** (Ecto.NoResultsError)

  """
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc """
  Gets an organization by name.

  ## Examples

      iex> get_organization_by_name("PJX")
      %Organization{}

      iex> get_organization_by_name("Unknown")
      nil

  """
  def get_organization_by_name(name) do
    Repo.get_by(Organization, name: name)
  end

  @doc """
  Gets the user's organization via the organization_users join table.

  This is the primary way to scope queries by organization - always get the org
  through the user, never hardcode organization IDs.

  ## Examples

      iex> get_user_organization(user)
      %Organization{}

      iex> get_user_organization(user_without_org)
      nil

  """
  def get_user_organization(user) do
    from(o in Organization,
      join: ou in OrganizationUser,
      on: ou.organization_id == o.id,
      where: ou.user_id == ^user.id,
      select: o
    )
    |> Repo.one()
  end

  @doc """
  Creates an organization.

  ## Examples

      iex> create_organization(%{field: value})
      {:ok, %Organization{}}

      iex> create_organization(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_organization(attrs \\ %{}) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an organization.

  ## Examples

      iex> update_organization(organization, %{field: new_value})
      {:ok, %Organization{}}

      iex> update_organization(organization, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an organization.

  ## Examples

      iex> delete_organization(organization)
      {:ok, %Organization{}}

      iex> delete_organization(organization)
      {:error, %Ecto.Changeset{}}

  """
  def delete_organization(%Organization{} = organization) do
    Repo.delete(organization)
  end

  @doc """
  Adds a user to an organization.

  ## Examples

      iex> add_user_to_organization(organization, user)
      {:ok, %OrganizationUser{}}

      iex> add_user_to_organization(organization, user)
      {:error, %Ecto.Changeset{}}

  """
  def add_user_to_organization(%Organization{} = organization, user) do
    %OrganizationUser{}
    |> OrganizationUser.changeset(%{
      organization_id: organization.id,
      user_id: user.id
    })
    |> Repo.insert()
  end

  @doc """
  Removes a user from an organization.

  ## Examples

      iex> remove_user_from_organization(organization, user)
      {:ok, %OrganizationUser{}}

  """
  def remove_user_from_organization(%Organization{} = organization, user) do
    from(ou in OrganizationUser,
      where: ou.organization_id == ^organization.id,
      where: ou.user_id == ^user.id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      organization_user -> Repo.delete(organization_user)
    end
  end

  @doc """
  Lists all users in an organization.

  ## Examples

      iex> list_organization_users(organization)
      [%User{}, ...]

  """
  def list_organization_users(%Organization{} = organization) do
    organization
    |> Repo.preload(:users)
    |> Map.get(:users)
  end
end
