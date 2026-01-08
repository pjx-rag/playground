defmodule Playground.Workers.DatabaseBackupWorkerTest do
  use Playground.DataCase, async: false
  use Oban.Testing, repo: Playground.Repo

  alias Playground.Workers.DatabaseBackupWorker

  describe "command injection prevention" do
    test "pg_dump uses argument list, not string interpolation" do
      # Read the source code to verify it uses proper argument lists
      source = File.read!("lib/playground/workers/database_backup_worker.ex")

      # Verify pg_dump is called with System.cmd/3 using argument list
      assert source =~ ~r/System\.cmd\(\s*pg_dump_path,\s*\[/
      assert source =~ ~r/"--no-owner"/
      assert source =~ ~r/"-f"/

      # Verify we're NOT using bash -c with string interpolation for dump
      refute source =~ ~r/System\.cmd\("bash",\s*\["-c",\s*dump_command/
    end

    test "sanitize uses argument list, not bash pipeline" do
      source = File.read!("lib/playground/workers/database_backup_worker.ex")

      # Verify gunzip, sed, and gzip are called separately with proper arguments
      assert source =~ ~r/System\.cmd\("gunzip"/
      assert source =~ ~r/System\.cmd\("sed"/
      assert source =~ ~r/System\.cmd\("gzip"/

      # Verify we're NOT using bash -c for sanitization
      refute source =~ ~r/gunzip -c.*\|.*sed.*\|.*gzip/
    end

    test "database_url is passed as argument, not interpolated" do
      source = File.read!("lib/playground/workers/database_backup_worker.ex")

      # Verify database_url appears in argument list
      assert source =~ ~r/database_url,\s*\n\s*"--no-owner"/

      # Verify we're not using the old vulnerable pattern with dump_command
      refute source =~ "dump_command = "
      refute source =~ ~r/System\.cmd\("bash",.*dump_command/
    end
  end

  describe "schedule_backup/1" do
    test "creates an Oban job" do
      assert {:ok, %Oban.Job{} = job} = DatabaseBackupWorker.schedule_backup()
      assert job.worker == "Playground.Workers.DatabaseBackupWorker"
      assert job.queue == "backups"
      assert job.args == %{"sanitize" => false}
    end

    test "can schedule with sanitize option" do
      assert {:ok, %Oban.Job{} = job} = DatabaseBackupWorker.schedule_backup(sanitize: true)
      assert job.args == %{"sanitize" => true}
    end
  end
end
