defmodule Playground.Workers.ConnectorSyncWorker do
  @moduledoc """
  Oban worker for syncing files from external connectors (Google Drive, etc.).

  Recursively fetches all files from the connector and stores them in the database.
  Updates connector status: awaiting_sync -> syncing -> synced
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Playground.Services.Connectors
  alias Playground.Files
  alias Playground.ApiTokens.TokenManager
  alias Playground.Services.Integrations.GoogleDrive

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"connector_org_id" => connector_org_id}}) do
    connector_org = Connectors.get_connector_organization!(connector_org_id)
    connector = Connectors.get_connector!(connector_org.connector_id)

    Logger.info("Starting sync for connector",
      connector_org_id: connector_org_id,
      connector_type: connector.key
    )

    # Update status to syncing
    {:ok, connector_org} = Connectors.update_connector_status(connector_org, "syncing")

    # Broadcast status change
    broadcast_status(connector_org_id, "syncing")

    result =
      case connector.key do
        "google_drive" -> sync_google_drive(connector_org)
        _ -> {:error, "Unknown connector type: #{connector.key}"}
      end

    case result do
      {:ok, file_count} ->
        # Update status to synced and set last_synced_at
        {:ok, _} = Connectors.update_connector_status(connector_org, "synced")
        {:ok, _} = Connectors.update_last_synced(connector_org)

        broadcast_status(connector_org_id, "synced")

        Logger.info("Sync completed",
          connector_org_id: connector_org_id,
          files_synced: file_count
        )

        :ok

      {:error, reason} ->
        # Revert to awaiting_sync on error
        {:ok, _} = Connectors.update_connector_status(connector_org, "awaiting_sync")
        broadcast_status(connector_org_id, "awaiting_sync")

        Logger.error("Sync failed",
          connector_org_id: connector_org_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp sync_google_drive(connector_org) do
    case TokenManager.get_valid_token("connector", connector_org.id) do
      {:ok, token} ->
        # Start recursive fetch from root
        fetch_folder_recursive(connector_org.id, token, "root", 0)

      {:error, reason} ->
        {:error, "Failed to get access token: #{inspect(reason)}"}
    end
  end

  defp fetch_folder_recursive(connector_org_id, token, folder_id, total_count) do
    case GoogleDrive.list_files(token, folder_id: folder_id) do
      {:ok, %{files: files}} ->
        # Store all files in database
        Enum.each(files, fn file_data ->
          parent_folder_id = List.first(file_data.parents)

          Files.upsert_file(%{
            connector_organization_id: connector_org_id,
            provider_file_id: file_data.id,
            parent_folder_id: parent_folder_id,
            name: file_data.name,
            mime_type: file_data.mime_type,
            size_bytes: file_data.size,
            metadata: file_data.metadata
          })
        end)

        new_count = total_count + length(files)

        # Broadcast progress
        broadcast_progress(connector_org_id, new_count)

        # Find folders and recursively fetch their contents
        folders =
          Enum.filter(files, fn f ->
            f.mime_type == "application/vnd.google-apps.folder"
          end)

        # Recursively process subfolders
        Enum.reduce_while(folders, {:ok, new_count}, fn folder, {:ok, count} ->
          case fetch_folder_recursive(connector_org_id, token, folder.id, count) do
            {:ok, updated_count} -> {:cont, {:ok, updated_count}}
            {:error, _} = error -> {:halt, error}
          end
        end)

      {:error, :unauthorized} ->
        {:error, "Token expired or invalid"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast_status(connector_org_id, status) do
    Phoenix.PubSub.broadcast(
      Playground.PubSub,
      "connector:#{connector_org_id}",
      {:connector_status_changed, status}
    )
  end

  defp broadcast_progress(connector_org_id, file_count) do
    Phoenix.PubSub.broadcast(
      Playground.PubSub,
      "connector:#{connector_org_id}",
      {:sync_progress, file_count}
    )
  end
end
