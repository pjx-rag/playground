defmodule PlaygroundWeb.AuthController do
  use PlaygroundWeb, :controller

  require Logger

  alias Playground.Connectors
  alias Playground.ApiTokens.TokenManager
  alias Playground.Organizations

  @doc """
  OAuth callback for Google Drive (and future providers).

  Handles the OAuth authorization code exchange and token storage.
  """
  def google_drive_callback(conn, %{"code" => code, "state" => state} = _params) do
    with {:ok, user_id, connector_id} <- verify_state(state),
         user <- Playground.Accounts.get_user!(user_id),
         connector <- Connectors.get_connector!(connector_id),
         org <- Organizations.get_user_organization(user),
         {:ok, token_data} <- Playground.Services.GoogleDrive.exchange_code(code),
         {:ok, connector_org} <- create_or_update_connector_org(org, connector, user),
         {:ok, _api_token} <- TokenManager.store_token("connector", connector_org.id, token_data),
         {:ok, _connector_org} <-
           update_connector_metadata(connector_org, token_data.access_token) do
      conn
      |> put_flash(:info, "Successfully connected #{connector.name}")
      |> redirect(to: ~p"/admin/connectors")
    else
      {:error, :invalid_state} ->
        Logger.warning("Invalid OAuth state parameter received")

        conn
        |> put_flash(:error, "Invalid authorization request. Please try again.")
        |> redirect(to: ~p"/admin/connectors")

      {:error, reason} ->
        Logger.error("OAuth callback failed", error: inspect(reason))

        conn
        |> put_flash(:error, "Failed to connect. Please try again.")
        |> redirect(to: ~p"/admin/connectors")
    end
  end

  def google_drive_callback(conn, %{"error" => error} = params) do
    Logger.warning("OAuth authorization denied", error: error, params: params)

    conn
    |> put_flash(:error, "Authorization was cancelled or denied.")
    |> redirect(to: ~p"/admin/connectors")
  end

  def google_drive_callback(conn, _params) do
    Logger.warning("OAuth callback called with missing parameters")

    conn
    |> put_flash(:error, "Invalid callback parameters.")
    |> redirect(to: ~p"/admin/connectors")
  end

  ## Private Functions

  defp verify_state(state) do
    case String.split(state, ":", parts: 3) do
      [user_id_str, connector_id_str, signature] ->
        data = "#{user_id_str}:#{connector_id_str}"
        expected_signature = :crypto.mac(:hmac, :sha256, state_secret(), data) |> Base.encode64()

        if signature == expected_signature do
          {:ok, String.to_integer(user_id_str), String.to_integer(connector_id_str)}
        else
          {:error, :invalid_state}
        end

      _ ->
        {:error, :invalid_state}
    end
  end

  defp state_secret do
    Application.fetch_env!(:playground, PlaygroundWeb.Endpoint)[:secret_key_base]
    |> binary_part(0, 32)
  end

  defp create_or_update_connector_org(org, connector, user) do
    case Connectors.get_organization_connector_by_key(user, connector.key) do
      nil ->
        # Create new connector organization - awaiting initial sync
        Connectors.create_connector_organization(%{
          organization_id: org.id,
          connector_id: connector.id,
          user_id: user.id,
          status: "awaiting_sync"
        })

      existing ->
        # Update existing connector - needs re-sync
        Connectors.update_connector_organization(existing, %{status: "awaiting_sync"})
    end
  end

  defp update_connector_metadata(connector_org, access_token) do
    # Fetch user info from Google to store email/name
    case fetch_google_user_info(access_token) do
      {:ok, user_info} ->
        metadata = %{
          email: user_info["email"],
          name: user_info["name"],
          picture: user_info["picture"]
        }

        Connectors.update_connector_metadata(connector_org, metadata)

      {:error, _reason} ->
        # Not critical, just skip metadata update
        {:ok, connector_org}
    end
  end

  defp fetch_google_user_info(access_token) do
    url = "https://www.googleapis.com/oauth2/v2/userinfo"

    case Req.get(url, auth: {:bearer, access_token}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.warning("Failed to fetch Google user info", status: status)
        {:error, :fetch_failed}

      {:error, reason} ->
        Logger.error("Network error fetching Google user info", error: inspect(reason))
        {:error, :network_error}
    end
  end
end
