defmodule PlaygroundWeb.AdminBackupsLive.Index do
  @moduledoc """
  Admin page for managing database backups.
  Allows viewing, creating, downloading, and deleting database backups.
  """
  use PlaygroundWeb, :live_view

  alias Playground.Workers.DatabaseBackupWorker
  import PlaygroundWeb.Components.Layout.PageLayout

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Playground.PubSub, "database_backups")
    end

    current_env = get_current_environment()
    backups = load_backups()

    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "Database Backups", path: nil}
    ]

    {:ok,
     socket
     |> assign(:page_title, "Database Backups")
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:backups, backups)
     |> assign(:current_environment, current_env)
     |> assign(:backup_in_progress, false)
     |> assign(:selected_backup, nil)
     |> assign(:show_restore_modal, false)}
  end

  @impl true
  def handle_event("create_backup", _params, socket) do
    case DatabaseBackupWorker.schedule_backup() do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:backup_in_progress, true)
         |> put_flash(:info, "Backup job scheduled. This may take a few minutes.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to schedule backup: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("download_backup", %{"key" => key}, socket) do
    config = Application.get_env(:playground, :storage)
    bucket = config[:bucket]
    filename = Path.basename(key)

    {:noreply,
     socket
     |> put_flash(
       :info,
       "To download: aws s3 cp s3://#{bucket}/#{key} ./#{filename} --endpoint-url https://fly.storage.tigris.dev"
     )}
  end

  @impl true
  def handle_event("delete_backup", %{"key" => key}, socket) do
    case DatabaseBackupWorker.delete_backup(key) do
      :ok ->
        backups = load_backups()

        {:noreply,
         socket
         |> assign(:backups, backups)
         |> put_flash(:info, "Backup deleted successfully.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete backup: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("refresh_backups", _params, socket) do
    backups = load_backups()
    {:noreply, assign(socket, :backups, backups)}
  end

  # PubSub handlers for real-time updates
  @impl true
  def handle_info({:backup_completed, _result}, socket) do
    backups = load_backups()

    {:noreply,
     socket
     |> assign(:backups, backups)
     |> assign(:backup_in_progress, false)
     |> put_flash(:info, "Backup completed successfully!")}
  end

  @impl true
  def handle_info({:backup_failed, %{reason: reason}}, socket) do
    {:noreply,
     socket
     |> assign(:backup_in_progress, false)
     |> put_flash(:error, "Backup failed: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({:backup_deleted, _result}, socket) do
    backups = load_backups()
    {:noreply, assign(socket, :backups, backups)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_backups do
    case DatabaseBackupWorker.list_backups() do
      {:ok, backups} ->
        Enum.sort_by(backups, & &1.last_modified, {:desc, DateTime})

      {:error, _} ->
        []
    end
  end

  defp get_current_environment do
    cond do
      Application.get_env(:playground, :environment) == :prod -> "production"
      Application.get_env(:playground, :environment) == :staging -> "staging"
      true -> "development"
    end
  end

  defp format_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_size(_), do: "Unknown"

  defp format_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %Y at %I:%M %p UTC")
      _ -> date_string
    end
  end

  defp format_date(_), do: "Unknown"

  defp environment_badge_class(env) do
    case env do
      "production" -> "bg-danger-soft text-foreground-danger-soft border-danger"
      "staging" -> "bg-warning-soft text-foreground-warning-soft border-warning"
      "development" -> "bg-success-soft text-foreground-success-soft border-success"
      _ -> "bg-muted text-muted-foreground border-base"
    end
  end
end
