defmodule Playground.ApiTokens.TokenManager do
  @moduledoc """
  Manages OAuth token lifecycle with database row locking to prevent race conditions.

  Based on enventory's EbayTokenManager pattern, this module uses Postgres row-level
  locking (SELECT FOR UPDATE) to ensure only one process can refresh a token at a time.

  ## Usage

      # Get a valid token (refreshes if needed)
      {:ok, token} = TokenManager.get_valid_token("connector", connector_org_id)

      # Use the token
      GoogleDrive.list_files(token)

  ## Race Condition Prevention

  Multiple processes trying to refresh the same token simultaneously will:
  1. First process acquires row lock via SELECT FOR UPDATE
  2. Other processes wait for lock to be released
  3. First process refreshes token and updates database
  4. Lock releases, waiting processes see fresh token
  5. Waiting processes skip refresh since token is now valid

  ## Token Refresh Flow

  1. Lock the api_tokens row (blocking)
  2. Check if token still needs refresh (may have been refreshed while waiting)
  3. If fresh, return it immediately
  4. If expired/expiring, call service to refresh
  5. Update database with new token
  6. Release lock and return new token
  """

  require Logger

  import Ecto.Query
  alias Playground.Repo
  alias Playground.ApiTokens
  alias Playground.ApiTokens.ApiToken

  @doc """
  Gets a valid access token for a resource, refreshing if necessary.

  This function handles all token lifecycle management:
  - Returns existing token if valid
  - Refreshes token if expiring within threshold
  - Uses database locking to prevent concurrent refresh attempts

  ## Parameters
    - `resource_type` - Type of resource (e.g., "connector", "integration")
    - `resource_id` - ID of the resource
    - `opts` - Options:
      - `:refresh_threshold` - Seconds before expiry to refresh (default: 300 = 5 minutes)
      - `:service_module` - Module to use for refresh (auto-detected if not provided)

  ## Returns
    - `{:ok, access_token}` - Valid access token string
    - `{:error, :not_found}` - No token exists for this resource
    - `{:error, :no_refresh_token}` - Token expired and no refresh token available
    - `{:error, reason}` - Other errors

  ## Examples

      # Get token for a connector
      {:ok, token} = TokenManager.get_valid_token("connector", 123)

      # Get token with custom refresh threshold
      {:ok, token} = TokenManager.get_valid_token("connector", 123, refresh_threshold: 600)

      # Specify service module explicitly
      {:ok, token} = TokenManager.get_valid_token(
        "connector",
        123,
        service_module: Playground.Services.GoogleDrive
      )

  """
  def get_valid_token(resource_type, resource_id, opts \\ []) do
    refresh_threshold = Keyword.get(opts, :refresh_threshold, 300)

    Repo.transaction(fn ->
      # Lock the row for update to prevent concurrent refresh attempts
      api_token =
        from(t in ApiToken,
          where: t.resource_type == ^resource_type and t.resource_id == ^resource_id,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      case api_token do
        nil ->
          Repo.rollback(:not_found)

        token ->
          if token_valid?(token, refresh_threshold) do
            token.access_token
          else
            refresh_token_locked(token, opts)
          end
      end
    end)
  end

  @doc """
  Stores a new token for a resource (typically after OAuth authorization).

  Uses upsert to handle both initial token creation and updates.

  ## Parameters
    - `resource_type` - Type of resource
    - `resource_id` - ID of the resource
    - `token_data` - Map with keys:
      - `:access_token` (required)
      - `:refresh_token` (optional)
      - `:expires_at` (required)
      - `:token_type` (optional, defaults to "Bearer")
      - `:scope` (optional)

  ## Returns
    - `{:ok, api_token}` - Token stored successfully
    - `{:error, changeset}` - Validation errors
  """
  def store_token(resource_type, resource_id, token_data) do
    attrs =
      token_data
      |> Map.put(:resource_type, resource_type)
      |> Map.put(:resource_id, resource_id)

    ApiTokens.upsert_token(attrs)
  end

  @doc """
  Revokes and deletes a token for a resource.

  ## Parameters
    - `resource_type` - Type of resource
    - `resource_id` - ID of the resource

  ## Returns
    - `{:ok, api_token}` - Token deleted
    - `{:error, :not_found}` - Token doesn't exist
  """
  def revoke_token(resource_type, resource_id) do
    case ApiTokens.get_token(resource_type, resource_id) do
      nil ->
        {:error, :not_found}

      token ->
        # Optionally call provider's revoke endpoint here
        # For Google: POST to https://oauth2.googleapis.com/revoke
        ApiTokens.delete_token(token)
    end
  end

  @doc """
  Checks if a token needs refresh soon.

  ## Parameters
    - `api_token` - ApiToken struct
    - `threshold_seconds` - Seconds before expiry to consider "needs refresh"

  ## Returns
    - `true` if token is expired or expiring within threshold
    - `false` if token is still valid
  """
  def needs_refresh?(api_token, threshold_seconds \\ 300) do
    not token_valid?(api_token, threshold_seconds)
  end

  ## Private Functions

  # Refreshes a token that is already locked via SELECT FOR UPDATE
  defp refresh_token_locked(api_token, opts) do
    unless api_token.refresh_token do
      Logger.error("Token expired with no refresh token",
        resource_type: api_token.resource_type,
        resource_id: api_token.resource_id
      )

      Repo.rollback(:no_refresh_token)
    end

    service_module = get_service_module(api_token, opts)

    Logger.info("Refreshing OAuth token",
      resource_type: api_token.resource_type,
      resource_id: api_token.resource_id,
      service: service_module
    )

    case service_module.refresh_token(api_token.refresh_token) do
      {:ok, new_token_data} ->
        case ApiTokens.refresh_token(api_token, new_token_data) do
          {:ok, updated_token} ->
            Logger.info("Token refreshed successfully",
              resource_type: api_token.resource_type,
              resource_id: api_token.resource_id
            )

            updated_token.access_token

          {:error, changeset} ->
            Logger.error("Failed to save refreshed token",
              resource_type: api_token.resource_type,
              resource_id: api_token.resource_id,
              errors: changeset.errors
            )

            Repo.rollback({:refresh_failed, "Database update failed"})
        end

      {:error, reason} ->
        Logger.error("Failed to refresh token from provider",
          resource_type: api_token.resource_type,
          resource_id: api_token.resource_id,
          error: reason
        )

        Repo.rollback({:refresh_failed, reason})
    end
  end

  # Determines which service module to use for token refresh
  defp get_service_module(api_token, opts) do
    case Keyword.get(opts, :service_module) do
      nil -> resolve_service_module(api_token)
      module -> module
    end
  end

  # Maps resource types to their service modules
  defp resolve_service_module(%{resource_type: "connector", resource_id: resource_id}) do
    # For connectors, look up which connector type this is
    connector_org = Playground.Connectors.get_connector_organization!(resource_id)
    connector = connector_org.connector

    case connector.key do
      "google_drive" -> Playground.Services.GoogleDrive
      # Future: "dropbox" -> Playground.Services.Dropbox
      _ -> raise "Unknown connector type: #{connector.key}"
    end
  end

  defp resolve_service_module(%{resource_type: type}) do
    raise "Unknown resource type: #{type}"
  end

  # Checks if token is still valid
  defp token_valid?(api_token, threshold_seconds) do
    case api_token.expires_at do
      nil ->
        # Token doesn't expire (shouldn't happen with OAuth, but handle gracefully)
        true

      expires_at ->
        threshold = DateTime.utc_now() |> DateTime.add(threshold_seconds, :second)
        DateTime.compare(expires_at, threshold) == :gt
    end
  end
end
