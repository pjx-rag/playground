#!/usr/bin/env elixir

# Start the application
Application.put_env(:playground, Playground.Repo,
  database: "playground_dev",
  username: System.get_env("PGUSER") || System.get_env("USER"),
  password: System.get_env("PGPASSWORD") || "",
  hostname: System.get_env("PGHOST") || "localhost",
  port: String.to_integer(System.get_env("PGPORT") || "5432")
)

Mix.install([
  {:ecto_sql, "~> 3.10"},
  {:postgrex, "~> 0.19"}
])

defmodule Repo do
  use Ecto.Repo,
    otp_app: :playground,
    adapter: Ecto.Adapters.Postgres
end

# Start the repo
{:ok, _} = Repo.start_link()

# Query file status
file_id = 35628

result = Repo.query!("""
  SELECT
    id,
    name,
    processing_status,
    sync_status,
    processing_attempt,
    processing_claimed_at,
    updated_at
  FROM files
  WHERE id = $1
""", [file_id])

IO.puts("\n📄 File #{file_id} Status:")
IO.puts("=" <> String.duplicate("=", 60))

case result.rows do
  [[id, name, proc_status, sync_status, attempts, claimed_at, updated_at]] ->
    IO.puts("  Name: #{name}")
    IO.puts("  Processing Status: #{proc_status}")
    IO.puts("  Sync Status: #{sync_status}")
    IO.puts("  Processing Attempts: #{attempts || 0}")
    IO.puts("  Claimed At: #{claimed_at || "not claimed"}")
    IO.puts("  Updated At: #{updated_at}")

  [] ->
    IO.puts("  File not found!")
end

# Check awaiting files
awaiting = Repo.query!("""
  SELECT id, name, updated_at
  FROM files
  WHERE processing_status = 'awaiting_analysis'
  ORDER BY updated_at DESC
  LIMIT 5
""")

IO.puts("\n⏳ Files Awaiting Analysis:")
IO.puts("=" <> String.duplicate("=", 60))

case awaiting.rows do
  [] ->
    IO.puts("  None")
  rows ->
    Enum.each(rows, fn [id, name, updated_at] ->
      IO.puts("  [#{id}] #{name} (updated: #{updated_at})")
    end)
end

# Check recent events
events = Repo.query!("""
  SELECT event_type, metadata, inserted_at
  FROM event_logs
  WHERE file_id = $1
  ORDER BY inserted_at DESC
  LIMIT 5
""", [file_id])

IO.puts("\n📋 Recent Events for File #{file_id}:")
IO.puts("=" <> String.duplicate("=", 60))

case events.rows do
  [] ->
    IO.puts("  No events found")
  rows ->
    Enum.each(rows, fn [event_type, metadata, inserted_at] ->
      IO.puts("  #{inserted_at} - #{event_type}")
      if metadata do
        IO.puts("    Metadata: #{inspect(metadata, pretty: true, width: 60)}")
      end
    end)
end

IO.puts("")
