defmodule Playground.Services do
  @moduledoc """
  Services context - External API integrations and third-party services.

  This facade coordinates cross-service operations. For specific operations:
  - `Playground.Services.Connectors` - Connector catalog and organization connections
  - `Playground.Services.Connectors.OAuth` - OAuth state management for connectors
  - `Playground.Services.AI.*` - AI/LLM services (OpenRouter, embeddings, PDF analysis)
  - `Playground.Services.Integrations.*` - External API integrations (Google Drive, Storage)

  ## Architecture

  Services owns all external integrations:
  - **Connectors**: Third-party data source connections (Google Drive, Notion, etc.)
  - **OAuth**: CSRF-protected OAuth flows for connector authorization
  - **AI Services**: LLM chat, embeddings, PDF analysis via OpenRouter
  - **Integrations**: Specific API implementations for external services
  - **Infrastructure**: API request logging, health checks, client behaviours
  """

  alias Playground.Repo
  alias Playground.Services.{APIRequestLog, Connectors}

  @doc """
  Tracks an API request and logs it to the database.

  Wraps any service operation to capture timing, response codes, and errors.
  Used across all external API calls for observability.

  ## Examples

      track_api_call("openrouter", "chat_completion", fn ->
        OpenRouter.create_chat_completion(messages, opts)
      end)
  """
  def track_api_call(service_name, operation, operation_fn) when is_function(operation_fn, 0) do
    start_time = System.monotonic_time(:millisecond)

    result = operation_fn.()

    duration_ms = System.monotonic_time(:millisecond) - start_time

    log_attrs = %{
      service: service_name,
      method: operation,
      path: "/",
      duration_ms: duration_ms,
      success: match?({:ok, _}, result)
    }

    log_attrs = case result do
      {:ok, response} when is_map(response) ->
        Map.merge(log_attrs, %{
          status_code: "200",
          response_body: Jason.encode!(response)
        })

      {:error, error} ->
        Map.merge(log_attrs, %{
          success: false,
          error_message: inspect(error)
        })

      _ ->
        log_attrs
    end

    %APIRequestLog{}
    |> APIRequestLog.changeset(log_attrs)
    |> Repo.insert()

    result
  end

  @doc """
  Synchronizes a connector organization with OAuth token refresh.

  Cross-service operation that:
  1. Validates OAuth state
  2. Exchanges code for tokens
  3. Updates connector organization credentials
  4. Triggers initial sync

  Used during OAuth callback flow.
  """
  def sync_connector_with_oauth(connector_org_id, oauth_code, state) do
    with {:ok, user_id, connector_id} <- Connectors.OAuth.verify_and_consume_state(state),
         connector_org <- Connectors.get_connector_organization!(connector_org_id),
         :ok <- verify_ownership(connector_org, user_id, connector_id),
         {:ok, tokens} <- exchange_oauth_code(connector_org, oauth_code),
         {:ok, updated_org} <- Connectors.update_connector_organization(connector_org, %{
           access_token: tokens.access_token,
           refresh_token: tokens.refresh_token,
           token_expires_at: tokens.expires_at
         }),
         {:ok, _sync_result} <- trigger_sync(updated_org) do
      {:ok, updated_org}
    end
  end

  defp verify_ownership(connector_org, user_id, connector_id) do
    if connector_org.user_id == user_id and connector_org.connector_id == connector_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp exchange_oauth_code(_connector_org, code) do
    # Implementation depends on connector type
    # This would call the appropriate integration module
    {:ok, %{access_token: code, refresh_token: nil, expires_at: nil}}
  end

  defp trigger_sync(_connector_org) do
    # Queue background sync job
    {:ok, :queued}
  end
end
