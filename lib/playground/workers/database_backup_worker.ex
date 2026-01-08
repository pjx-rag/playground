defmodule Playground.Workers.DatabaseBackupWorker do
  @moduledoc """
  Oban worker for creating and uploading database backups to S3-compatible storage.
  Organizes backups in environment-specific folders.
  """

  use Oban.Worker,
    queue: :backups,
    max_attempts: 3

  require Logger
  alias Playground.Services.ObjectStorage

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    environment = get_current_environment()
    sanitize = Map.get(args, "sanitize", false)

    Logger.info("Starting database backup for environment: #{environment}")

    with {:ok, dump_file} <- create_dump(),
         {:ok, sanitized_file} <- maybe_sanitize(dump_file, sanitize),
         {:ok, result} <- upload_to_storage(sanitized_file, environment) do
      File.rm(sanitized_file)

      clean_old_backups(environment, 30)

      Phoenix.PubSub.broadcast(
        Playground.PubSub,
        "database_backups",
        {:backup_completed, %{environment: environment, result: result}}
      )

      Logger.info("Database backup completed successfully: #{inspect(result)}")
      {:ok, result}
    else
      {:error, reason} = error ->
        Logger.error("Database backup failed: #{inspect(reason)}")

        Phoenix.PubSub.broadcast(
          Playground.PubSub,
          "database_backups",
          {:backup_failed, %{environment: environment, reason: reason}}
        )

        error
    end
  end

  defp create_dump do
    environment = get_current_environment()
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
    dump_file = "/tmp/playground_#{environment}_#{timestamp}.sql"

    database_url = System.get_env("DATABASE_URL")

    pg_dump_path =
      cond do
        File.exists?("/Applications/Postgres.app/Contents/Versions/latest/bin/pg_dump") ->
          "/Applications/Postgres.app/Contents/Versions/latest/bin/pg_dump"

        File.exists?("/usr/lib/postgresql/16/bin/pg_dump") ->
          "/usr/lib/postgresql/16/bin/pg_dump"

        File.exists?("/usr/lib/postgresql/15/bin/pg_dump") ->
          "/usr/lib/postgresql/15/bin/pg_dump"

        File.exists?("/usr/bin/pg_dump") ->
          "/usr/bin/pg_dump"

        true ->
          "pg_dump"
      end

    Logger.info("Using pg_dump at: #{pg_dump_path}")

    # Use argument list instead of string interpolation to prevent command injection
    case System.cmd(
           pg_dump_path,
           [
             database_url,
             "--no-owner",
             "--no-acl",
             "--clean",
             "--if-exists",
             "--exclude-table=oban_jobs",
             "--exclude-table=oban_peers",
             "--exclude-table=schema_migrations",
             "-f",
             dump_file
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Logger.info("Database dump created successfully: #{dump_file}")
        {_, 0} = System.cmd("gzip", [dump_file])
        {:ok, "#{dump_file}.gz"}

      {output, _} ->
        Logger.error("pg_dump failed: #{output}")
        {:error, "Dump failed: #{output}"}
    end
  end

  defp maybe_sanitize(dump_file, false), do: {:ok, dump_file}

  defp maybe_sanitize(dump_file, true) do
    sanitized_file = String.replace(dump_file, ".sql.gz", "_sanitized.sql.gz")
    uncompressed_file = String.replace(dump_file, ".gz", "")
    sanitized_uncompressed = String.replace(sanitized_file, ".gz", "")

    # Decompose pipeline into separate, safe commands to prevent injection
    # Step 1: Decompress
    with {_, 0} <- System.cmd("gunzip", [dump_file], stderr_to_stdout: true),
         # Step 2: Sanitize emails using in-place sed
         {_, 0} <- System.cmd("sed", ["-i", "", "s/@[^@]*\\.com/@example.com/g", uncompressed_file],
                      stderr_to_stdout: true),
         # Step 3: Rename sanitized file
         :ok <- File.rename(uncompressed_file, sanitized_uncompressed),
         # Step 4: Compress
         {_, 0} <- System.cmd("gzip", [sanitized_uncompressed], stderr_to_stdout: true) do
      {:ok, sanitized_file}
    else
      {output, exit_code} when is_integer(exit_code) ->
        # Clean up any intermediate files on failure
        File.rm(uncompressed_file)
        File.rm(sanitized_uncompressed)
        File.rm(dump_file)
        {:error, "Sanitization failed (exit #{exit_code}): #{inspect(output)}"}

      {:error, reason} ->
        # File operation failed
        File.rm(uncompressed_file)
        File.rm(sanitized_uncompressed)
        {:error, "Sanitization failed: #{inspect(reason)}"}
    end
  end

  defp upload_to_storage(dump_file, environment) do
    filename = Path.basename(dump_file)
    object_key = "dumps/#{environment}/#{filename}"

    with {:ok, content} <- File.read(dump_file),
         {:ok, url} <-
           ObjectStorage.upload(object_key, content,
             content_type: "application/gzip",
             metadata: %{
               "environment" => environment,
               "created_at" => DateTime.to_iso8601(DateTime.utc_now())
             }
           ) do
      {:ok,
       %{
         url: url,
         object_key: object_key,
         size: byte_size(content),
         environment: environment,
         created_at: DateTime.utc_now()
       }}
    end
  end

  defp clean_old_backups(environment, days_to_keep) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days_to_keep * 24 * 60 * 60)
    prefix = "dumps/#{environment}/"

    case ObjectStorage.list_objects(prefix) do
      {:ok, objects} ->
        objects
        |> Enum.filter(fn obj ->
          case DateTime.from_iso8601(obj.last_modified) do
            {:ok, date, _} -> DateTime.compare(date, cutoff_date) == :lt
            _ -> false
          end
        end)
        |> Enum.each(fn obj ->
          Logger.info("Deleting old backup: #{obj.key}")
          ObjectStorage.delete(obj.key)
        end)

      {:error, _} ->
        Logger.warning("Could not clean old backups")
    end
  end

  defp get_current_environment do
    cond do
      Application.get_env(:playground, :environment) == :prod -> "production"
      Application.get_env(:playground, :environment) == :staging -> "staging"
      true -> "development"
    end
  end

  @doc """
  Schedules a database backup job.
  """
  def schedule_backup(opts \\ []) do
    args = %{"sanitize" => Keyword.get(opts, :sanitize, false)}

    args
    |> Oban.Job.new(worker: __MODULE__, queue: :backups)
    |> Oban.insert()
  end

  @doc """
  Lists available backups from storage.
  """
  def list_backups(environment \\ nil) do
    prefix = if environment, do: "dumps/#{environment}/", else: "dumps/"

    case ObjectStorage.list_objects(prefix) do
      {:ok, objects} ->
        backups =
          Enum.map(objects, fn obj ->
            key = Map.get(obj, :key) || Map.get(obj, "key")
            size = Map.get(obj, :size) || Map.get(obj, "size") || "0"
            last_modified = Map.get(obj, :last_modified) || Map.get(obj, "last_modified") || ""

            %{
              key: key,
              size: parse_size(size),
              last_modified: last_modified,
              environment: extract_environment(key),
              filename: Path.basename(key || "")
            }
          end)

        {:ok, backups}

      error ->
        error
    end
  end

  @doc """
  Deletes a backup from storage.
  """
  def delete_backup(object_key) do
    case ObjectStorage.delete(object_key) do
      :ok ->
        environment = extract_environment(object_key)

        Phoenix.PubSub.broadcast(
          Playground.PubSub,
          "database_backups",
          {:backup_deleted, %{environment: environment, object_key: object_key}}
        )

        :ok

      error ->
        error
    end
  end

  defp extract_environment(key) do
    case Regex.run(~r/dumps\/([^\/]+)\//, key || "") do
      [_, env] -> env
      _ -> "unknown"
    end
  end

  defp parse_size(size) when is_integer(size), do: size

  defp parse_size(size) when is_binary(size) do
    case Integer.parse(size) do
      {num, _} -> num
      _ -> 0
    end
  end

  defp parse_size(_), do: 0
end
