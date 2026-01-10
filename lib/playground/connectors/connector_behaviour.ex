defmodule Playground.Connectors.ConnectorBehaviour do
  @moduledoc """
  Behaviour for connector implementations (Google Drive, Dropbox, etc.).

  This behaviour defines the interface for connector operations like listing files,
  getting file metadata, and browsing folders. OAuth functionality is handled by
  the service layer (Playground.APIClient behaviour).

  ## Responsibilities

  This behaviour handles:
  - Listing files and folders
  - Getting file metadata
  - Browsing folder contents
  - Pagination of results

  The service layer (APIClient behaviour) handles:
  - OAuth authorization URLs
  - Token exchange
  - Token refresh
  - API health checks
  """

  @doc """
  Lists files and folders with pagination support.

  ## Parameters
    - `token` - Access token for API authentication
    - `opts` - Keyword list of options:
      - `:page_token` - Token for next page of results
      - `:page_size` - Number of results per page (default varies by provider)
      - `:folder_id` - Optional folder ID to list contents of specific folder
      - `:query` - Optional search query

  ## Returns
    - `{:ok, %{files: [file_map], next_page_token: string | nil}}`
    - `{:error, reason}`

  ## File Map Structure
  Each file map should contain:
    - `:id` - Provider's stable file ID
    - `:name` - File name
    - `:mime_type` - MIME type (e.g., "application/pdf")
    - `:size` - Size in bytes (may be nil for folders)
    - `:modified_time` - Last modified timestamp
    - `:is_folder` - Boolean indicating if this is a folder
    - `:parents` - List of parent folder IDs
    - `:metadata` - Map of additional provider-specific metadata
  """
  @callback list_files(token :: String.t(), opts :: Keyword.t()) ::
              {:ok, %{files: [map()], next_page_token: String.t() | nil}}
              | {:error, any()}

  @doc """
  Gets metadata for a specific file.

  ## Parameters
    - `token` - Access token for API authentication
    - `file_id` - Provider's file ID

  ## Returns
    - `{:ok, file_map}` - Same structure as in list_files/2
    - `{:error, reason}`
  """
  @callback get_file_metadata(token :: String.t(), file_id :: String.t()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Gets the contents of a specific folder.

  This is a convenience function that wraps list_files/2 with a folder_id filter.

  ## Parameters
    - `token` - Access token for API authentication
    - `folder_id` - Provider's folder ID
    - `opts` - Keyword list of options (same as list_files/2)

  ## Returns
    - `{:ok, %{files: [file_map], next_page_token: string | nil}}`
    - `{:error, reason}`
  """
  @callback get_folder_contents(
              token :: String.t(),
              folder_id :: String.t(),
              opts :: Keyword.t()
            ) ::
              {:ok, %{files: [map()], next_page_token: String.t() | nil}}
              | {:error, any()}

  @doc """
  Downloads a file's content.

  ## Parameters
    - `token` - Access token for API authentication
    - `file_id` - Provider's file ID
    - `opts` - Keyword list of options:
      - `:stream` - If true, returns a stream; if false, returns binary (default: false)
      - `:export_format` - For native formats (Google Docs), export format (e.g., "text/plain")

  ## Returns
    - When `stream: false`: `{:ok, binary}` - File content as binary
    - When `stream: true`: `{:ok, stream}` - File content as enumerable stream
    - `{:error, reason}`

  ## Examples

      # Download as binary
      {:ok, content} = get_file(token, "file123", stream: false)

      # Download as stream for large files
      {:ok, stream} = get_file(token, "file123", stream: true)
      chunks = Enum.to_list(stream)

  """
  @callback get_file(token :: String.t(), file_id :: String.t(), opts :: Keyword.t()) ::
              {:ok, binary() | Enumerable.t()} | {:error, any()}
end
