defmodule Playground.Services.GoogleDrive do
  @moduledoc """
  Google Drive API client implementing both APIClient and ConnectorBehaviour.

  ## OAuth Flow
  1. Generate authorization URL with `authorize_url/1`
  2. User grants consent in browser
  3. Exchange authorization code for tokens with `exchange_code/1`
  4. Store tokens in api_tokens table
  5. Refresh tokens before expiry with `refresh_token/1`

  ## API Documentation
  - OAuth: https://developers.google.com/identity/protocols/oauth2
  - Drive API: https://developers.google.com/drive/api/v3/reference
  """

  @behaviour Playground.APIClient
  @behaviour Playground.Connectors.ConnectorBehaviour

  require Logger

  # OAuth endpoints
  @auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"

  # API endpoints
  @base_url "https://www.googleapis.com/drive/v3"

  # OAuth scopes - drive.readonly allows listing and reading files
  @default_scopes [
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/userinfo.email"
  ]

  ## APIClient Behaviour Implementation

  @impl Playground.APIClient
  def service_name, do: "Google Drive"

  @impl Playground.APIClient
  def base_url, do: @base_url

  @impl Playground.APIClient
  def health_check do
    # Check if Google Drive API is reachable without requiring a customer token
    # Uses the public discovery document endpoint which doesn't require authentication
    start_time = System.monotonic_time(:millisecond)

    case Req.get("https://www.googleapis.com/discovery/v1/apis/drive/v3/rest") do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        latency_ms = System.monotonic_time(:millisecond) - start_time

        # Verify OAuth configuration is present
        config_status = check_oauth_config()

        {:ok, %{
          status: :healthy,
          latency_ms: latency_ms,
          message: "Google Drive API is reachable",
          oauth_configured: config_status
        }}

      {:ok, %{status: status}} ->
        {:error, %{
          status: :degraded,
          message: "Google API returned unexpected status: #{status}",
          oauth_configured: check_oauth_config()
        }}

      {:error, reason} ->
        {:error, %{
          status: :unhealthy,
          message: "Cannot reach Google Drive API: #{inspect(reason)}",
          oauth_configured: check_oauth_config()
        }}
    end
  end

  defp check_oauth_config do
    client_id = Application.get_env(:playground, :google_drive)[:client_id]
    client_secret = Application.get_env(:playground, :google_drive)[:client_secret]

    cond do
      is_nil(client_id) or client_id == "" ->
        {:error, "GOOGLE_DRIVE_CLIENT_ID not configured"}
      is_nil(client_secret) or client_secret == "" ->
        {:error, "GOOGLE_DRIVE_CLIENT_SECRET not configured"}
      true ->
        :ok
    end
  end

  @impl Playground.APIClient
  def default_headers do
    [{"content-type", "application/json"}]
  end

  @doc """
  Health check with access token to verify token validity.
  """
  def health_check_with_token(access_token) do
    # Ping the about endpoint to verify token validity
    case Req.get(build_req(access_token), url: "/about", params: [fields: "user"]) do
      {:ok, %{status: 200}} ->
        {:ok, %{status: :healthy, message: "Google Drive API accessible"}}

      {:ok, %{status: 401}} ->
        {:error, %{status: :unhealthy, message: "Invalid or expired token"}}

      {:ok, %{status: 403}} ->
        {:error, %{status: :unhealthy, message: "Access forbidden - check scopes"}}

      {:ok, %{status: status}} ->
        {:error, %{status: :degraded, message: "Unexpected status: #{status}"}}

      {:error, reason} ->
        {:error, %{status: :unhealthy, message: "Connection failed: #{inspect(reason)}"}}
    end
  end

  ## OAuth Methods (not part of APIClient behaviour)

  @doc """
  Generates OAuth authorization URL for user consent.
  """
  def authorize_url(opts \\ []) do
    client_id = get_client_id!()
    redirect_uri = get_redirect_uri!()
    state = Keyword.get(opts, :state, generate_state())
    scopes = Keyword.get(opts, :scopes, @default_scopes)

    params = %{
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: Enum.join(scopes, " "),
      state: state,
      access_type: "offline",
      # Force consent to ensure we get a refresh token
      prompt: "consent"
    }

    "#{@auth_url}?#{URI.encode_query(params)}"
  end

  @doc """
  Exchanges authorization code for OAuth tokens.
  """
  def exchange_code(code, opts \\ []) do
    client_id = get_client_id!()
    client_secret = get_client_secret!()
    redirect_uri = Keyword.get(opts, :redirect_uri, get_redirect_uri!())

    body = %{
      code: code,
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    }

    case Req.post(@token_url, json: body) do
      {:ok, %{status: 200, body: response}} ->
        parse_token_response(response)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google OAuth token exchange failed",
          status: status,
          error: body["error"],
          description: body["error_description"]
        )

        {:error, body["error_description"] || "Token exchange failed"}

      {:error, reason} ->
        Logger.error("Google OAuth token exchange request failed", error: inspect(reason))
        {:error, "Network error during token exchange"}
    end
  end

  @doc """
  Refreshes an expired OAuth token using the refresh token.
  """
  def refresh_token(refresh_token, _opts \\ []) do
    client_id = get_client_id!()
    client_secret = get_client_secret!()

    body = %{
      refresh_token: refresh_token,
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "refresh_token"
    }

    case Req.post(@token_url, json: body) do
      {:ok, %{status: 200, body: response}} ->
        parse_token_response(response)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google OAuth token refresh failed",
          status: status,
          error: body["error"],
          description: body["error_description"]
        )

        {:error, body["error_description"] || "Token refresh failed"}

      {:error, reason} ->
        Logger.error("Google OAuth token refresh request failed", error: inspect(reason))
        {:error, "Network error during token refresh"}
    end
  end

  ## ConnectorBehaviour Implementation

  @impl Playground.Connectors.ConnectorBehaviour
  def list_files(token, opts \\ []) do
    params =
      build_list_params(opts)
      |> Map.put(:fields, file_fields())

    case Req.get(build_req(token), url: "/files", params: params) do
      {:ok, %{status: 200, body: body}} ->
        files = Enum.map(body["files"] || [], &normalize_file/1)
        {:ok, %{files: files, next_page_token: body["nextPageToken"]}}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Drive list files failed", status: status, error: body)
        {:error, "Failed to list files: #{status}"}

      {:error, reason} ->
        Logger.error("Google Drive list files request failed", error: inspect(reason))
        {:error, "Network error"}
    end
  end

  @impl Playground.Connectors.ConnectorBehaviour
  def get_file_metadata(token, file_id) do
    params = %{fields: file_fields()}

    case Req.get(build_req(token), url: "/files/#{file_id}", params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, normalize_file(body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Drive get file metadata failed", status: status, error: body)
        {:error, "Failed to get file metadata: #{status}"}

      {:error, reason} ->
        Logger.error("Google Drive get file metadata request failed", error: inspect(reason))
        {:error, "Network error"}
    end
  end

  @impl Playground.Connectors.ConnectorBehaviour
  def get_folder_contents(token, folder_id, opts \\ []) do
    # Add folder filter to query
    opts = Keyword.put(opts, :folder_id, folder_id)
    list_files(token, opts)
  end

  @impl Playground.Connectors.ConnectorBehaviour
  def get_file(token, file_id, opts \\ []) do
    stream? = Keyword.get(opts, :stream, false)
    export_format = Keyword.get(opts, :export_format)

    # Use alt=media to download the actual file content
    # For Google Docs native formats, use /export endpoint
    url =
      if export_format do
        "https://www.googleapis.com/drive/v3/files/#{file_id}/export?mimeType=#{URI.encode_www_form(export_format)}"
      else
        "https://www.googleapis.com/drive/v3/files/#{file_id}?alt=media"
      end

    # Don't use streaming for now - download the full content
    case Req.get(build_req(token), url: url) do
      {:ok, %{status: 200, body: body}} ->
        if stream? do
          # Return as stream - wrap binary content in a stream for compatibility
          {:ok, Stream.map([body], & &1)}
        else
          # Return as binary
          {:ok, body}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Drive download failed", status: status, file_id: file_id, body: inspect(body))
        {:error, "Download failed with status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Helpers

  defp build_req(access_token) do
    Req.new(
      base_url: @base_url,
      auth: {:bearer, access_token},
      retry: :transient,
      max_retries: 3
    )
  end

  defp build_list_params(opts) do
    params = %{
      pageSize: Keyword.get(opts, :page_size, 100),
      orderBy: "folder,name"
    }

    params =
      if page_token = Keyword.get(opts, :page_token) do
        Map.put(params, :pageToken, page_token)
      else
        params
      end

    params =
      if folder_id = Keyword.get(opts, :folder_id) do
        query = "'#{folder_id}' in parents and trashed = false"
        Map.put(params, :q, query)
      else
        # Default: show root-level files only (in 'My Drive' root folder)
        Map.put(params, :q, "'root' in parents and trashed = false")
      end

    params
  end

  defp file_fields do
    "files(id,name,mimeType,size,modifiedTime,parents,webViewLink,thumbnailLink,trashed),nextPageToken"
  end

  defp normalize_file(file_data) do
    %{
      id: file_data["id"],
      name: file_data["name"],
      mime_type: file_data["mimeType"],
      size: parse_size(file_data["size"]),
      modified_time: parse_datetime(file_data["modifiedTime"]),
      is_folder: file_data["mimeType"] == "application/vnd.google-apps.folder",
      parents: file_data["parents"] || [],
      metadata: %{
        web_view_link: file_data["webViewLink"],
        thumbnail_link: file_data["thumbnailLink"],
        trashed: file_data["trashed"] || false
      }
    }
  end

  defp parse_size(nil), do: nil
  defp parse_size(size) when is_binary(size), do: String.to_integer(size)
  defp parse_size(size) when is_integer(size), do: size

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_token_response(response) do
    expires_in = response["expires_in"] || 3600
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second)

    {:ok,
     %{
       access_token: response["access_token"],
       refresh_token: response["refresh_token"],
       expires_at: expires_at,
       token_type: response["token_type"] || "Bearer",
       scope: response["scope"]
     }}
  end

  defp get_client_id! do
    Application.fetch_env!(:playground, :google_drive)[:client_id]
  end

  defp get_client_secret! do
    Application.fetch_env!(:playground, :google_drive)[:client_secret]
  end

  defp get_redirect_uri! do
    Application.get_env(:playground, :google_drive)[:redirect_uri] ||
      "http://localhost:4000/auth/google_drive/callback"
  end

  defp generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
