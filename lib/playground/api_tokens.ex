defmodule Playground.ApiTokens do
  @moduledoc """
  The ApiTokens context.

  Generic polymorphic OAuth token storage for any integration.
  Works for connectors, external APIs, or any OAuth resource.
  """

  import Ecto.Query, warn: false
  alias Playground.Repo
  alias Playground.ApiTokens.ApiToken

  @doc """
  Gets a token for a specific resource.

  ## Examples

      iex> get_token("connector", 123)
      %ApiToken{}

      iex> get_token("connector", 456)
      nil

  """
  def get_token(resource_type, resource_id) do
    Repo.get_by(ApiToken, resource_type: resource_type, resource_id: resource_id)
  end

  @doc """
  Gets a token for a specific resource.

  Raises `Ecto.NoResultsError` if the ApiToken does not exist.

  ## Examples

      iex> get_token!("connector", 123)
      %ApiToken{}

      iex> get_token!("connector", 456)
      ** (Ecto.NoResultsError)

  """
  def get_token!(resource_type, resource_id) do
    Repo.get_by!(ApiToken, resource_type: resource_type, resource_id: resource_id)
  end

  @doc """
  Creates an api token.

  ## Examples

      iex> create_token(%{resource_type: "connector", resource_id: 1, access_token: "token"})
      {:ok, %ApiToken{}}

      iex> create_token(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_token(attrs \\ %{}) do
    %ApiToken{}
    |> ApiToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an api token.

  ## Examples

      iex> update_token(api_token, %{access_token: "new_token"})
      {:ok, %ApiToken{}}

      iex> update_token(api_token, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_token(%ApiToken{} = api_token, attrs) do
    api_token
    |> ApiToken.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Refreshes a token with new OAuth credentials.

  ## Examples

      iex> refresh_token(api_token, %{access_token: "new", expires_at: ~U[2024-01-01 00:00:00Z]})
      {:ok, %ApiToken{}}

  """
  def refresh_token(%ApiToken{} = api_token, attrs) do
    api_token
    |> ApiToken.refresh_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an api token.

  ## Examples

      iex> delete_token(api_token)
      {:ok, %ApiToken{}}

      iex> delete_token(api_token)
      {:error, %Ecto.Changeset{}}

  """
  def delete_token(%ApiToken{} = api_token) do
    Repo.delete(api_token)
  end

  @doc """
  Finds tokens that are expiring within the given minutes threshold.

  Used by Oban worker to proactively refresh tokens.

  ## Examples

      iex> find_expiring_tokens(10)
      [%ApiToken{}, ...]

  """
  def find_expiring_tokens(minutes_threshold \\ 10) do
    threshold = DateTime.utc_now() |> DateTime.add(minutes_threshold * 60, :second)

    from(t in ApiToken,
      where: t.expires_at <= ^threshold,
      where: not is_nil(t.refresh_token)
    )
    |> Repo.all()
  end

  @doc """
  Upserts a token (insert or update if exists).

  Useful for OAuth flows where we may be creating or refreshing.

  ## Examples

      iex> upsert_token(%{resource_type: "connector", resource_id: 1, access_token: "token"})
      {:ok, %ApiToken{}}

  """
  def upsert_token(attrs) do
    %ApiToken{}
    |> ApiToken.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:resource_type, :resource_id]
    )
  end

  @doc """
  Gets a valid (non-expired) token for a connector organization.

  Returns {:ok, token} if a valid token exists, or {:error, reason} otherwise.

  ## Examples

      iex> get_valid_token(connector_org_id, "Google Drive")
      {:ok, %ApiToken{}}

      iex> get_valid_token(connector_org_id, "Google Drive")
      {:error, :not_found}

      iex> get_valid_token(connector_org_id, "Google Drive")
      {:error, :expired}

  """
  def get_valid_token(connector_organization_id, _service_name) do
    case get_token("connector_organization", connector_organization_id) do
      nil ->
        {:error, :not_found}

      token ->
        if token.expires_at && DateTime.compare(token.expires_at, DateTime.utc_now()) == :lt do
          {:error, :expired}
        else
          {:ok, token}
        end
    end
  end
end
