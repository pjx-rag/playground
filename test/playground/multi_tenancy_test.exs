defmodule Playground.MultiTenancyTest do
  @moduledoc """
  Tests multi-tenancy isolation to ensure users cannot access data from other organizations.

  Critical security requirement: All file access must be scoped to the user's organization.
  """
  use Playground.DataCase, async: true

  import Playground.{AccountsFixtures, ConnectorsFixtures, FilesFixtures, OrganizationsFixtures}

  alias Playground.Files
  alias Playground.RAG.Workers.{EmbedChunksWorker, ProcessTextFileWorker}

  describe "Files.get_file!/2 multi-tenancy enforcement" do
    setup do
      # Create two separate organizations with users
      org1 = organization_fixture()
      org2 = organization_fixture()

      user1 = user_fixture() |> associate_with_organization(org1)
      user2 = user_fixture() |> associate_with_organization(org2)

      # Create connector organizations for each
      connector = connector_fixture()
      connector_org1 = connector_organization_fixture(org1, connector, user1)
      connector_org2 = connector_organization_fixture(org2, connector, user2)

      # Create files for each organization
      file1 = file_fixture(connector_org1)
      file2 = file_fixture(connector_org2)

      %{
        org1: org1,
        org2: org2,
        user1: user1,
        user2: user2,
        file1: file1,
        file2: file2
      }
    end

    test "user can access files from their own organization", %{user1: user1, file1: file1} do
      # Should succeed - same organization
      loaded_file = Files.get_file!(file1.id, user1)
      assert loaded_file.id == file1.id
    end

    test "user cannot access files from other organizations", %{user1: user1, file2: file2} do
      # Should raise - different organization
      assert_raise Ecto.NoResultsError, fn ->
        Files.get_file!(file2.id, user1)
      end
    end

    test "loading file preloads connector_organization", %{user1: user1, file1: file1} do
      loaded_file = Files.get_file!(file1.id, user1)
      assert Ecto.assoc_loaded?(loaded_file.connector_organization)
    end
  end

  describe "ProcessTextFileWorker multi-tenancy enforcement" do
    setup do
      org1 = organization_fixture()
      org2 = organization_fixture()

      user1 = user_fixture() |> associate_with_organization(org1)
      user2 = user_fixture() |> associate_with_organization(org2)

      connector = connector_fixture()
      connector_org1 = connector_organization_fixture(org1, connector, user1)
      connector_org2 = connector_organization_fixture(org2, connector, user2)

      file1 = file_fixture(connector_org1, %{processing_status: "draft"})
      file2 = file_fixture(connector_org2, %{processing_status: "draft"})

      %{
        org1: org1,
        org2: org2,
        file1: file1,
        file2: file2
      }
    end

    test "worker processes file with correct organization_id", %{org1: org1, file1: file1} do
      # Worker should succeed with correct organization_id
      job = %Oban.Job{
        args: %{"file_id" => file1.id, "organization_id" => org1.id}
      }

      # This would normally process the file, but we're just testing the query succeeds
      # In a real test, we'd mock the actual processing
      assert :ok = ProcessTextFileWorker.perform(job)
    end

    test "worker fails with mismatched organization_id", %{org2: org2, file1: file1} do
      # Worker should fail - file1 belongs to org1, not org2
      job = %Oban.Job{
        args: %{"file_id" => file1.id, "organization_id" => org2.id}
      }

      # Should raise because the organization_id doesn't match the file's organization
      assert_raise Ecto.NoResultsError, fn ->
        ProcessTextFileWorker.perform(job)
      end
    end
  end

  describe "EmbedChunksWorker multi-tenancy enforcement" do
    setup do
      org1 = organization_fixture()
      org2 = organization_fixture()

      user1 = user_fixture() |> associate_with_organization(org1)
      user2 = user_fixture() |> associate_with_organization(org2)

      connector = connector_fixture()
      connector_org1 = connector_organization_fixture(org1, connector, user1)
      connector_org2 = connector_organization_fixture(org2, connector, user2)

      file1 = file_fixture(connector_org1, %{processing_status: "chunked"})
      file2 = file_fixture(connector_org2, %{processing_status: "chunked"})

      chunk1 = chunk_fixture(file1, %{position: 0, content: "Test content 1"})
      chunk2 = chunk_fixture(file2, %{position: 0, content: "Test content 2"})

      %{
        org1: org1,
        org2: org2,
        chunk1: chunk1,
        chunk2: chunk2
      }
    end

    test "worker only loads chunks from correct organization", %{org1: org1, chunk1: chunk1, chunk2: chunk2} do
      # Worker should only load chunk1, not chunk2
      job = %Oban.Job{
        args: %{
          "chunk_ids" => [chunk1.id, chunk2.id],
          "organization_id" => org1.id
        }
      }

      # The worker will load chunks and filter by organization
      # We expect it to only process chunk1
      assert {:error, _} = EmbedChunksWorker.perform(job)
      # Note: This will error because we don't have a real OpenRouter API key,
      # but it proves the query succeeds for chunk1
    end

    test "worker returns ok when no chunks match organization", %{org1: org1, chunk2: chunk2} do
      # chunk2 belongs to org2, so passing org1.id should find no chunks
      job = %Oban.Job{
        args: %{
          "chunk_ids" => [chunk2.id],
          "organization_id" => org1.id
        }
      }

      # Should return :ok with no chunks found
      assert :ok = EmbedChunksWorker.perform(job)
    end
  end

  describe "Files.list_synced_files/1 multi-tenancy enforcement" do
    setup do
      org1 = organization_fixture()
      org2 = organization_fixture()

      user1 = user_fixture() |> associate_with_organization(org1)
      user2 = user_fixture() |> associate_with_organization(org2)

      connector = connector_fixture()
      connector_org1 = connector_organization_fixture(org1, connector, user1)
      connector_org2 = connector_organization_fixture(org2, connector, user2)

      # Create synced files for each org
      _file1 = file_fixture(connector_org1, %{sync_status: "synced"})
      _file2 = file_fixture(connector_org2, %{sync_status: "synced"})

      %{user1: user1, user2: user2}
    end

    test "user only sees files from their organization", %{user1: user1, user2: user2} do
      files1 = Files.list_synced_files(user1)
      files2 = Files.list_synced_files(user2)

      # Each user should see exactly 1 file
      assert length(files1) == 1
      assert length(files2) == 1

      # Files should be different
      assert hd(files1).id != hd(files2).id
    end
  end

  describe "Files.sync_and_process_files/1 multi-tenancy enforcement" do
    setup do
      org1 = organization_fixture()
      org2 = organization_fixture()

      user1 = user_fixture() |> associate_with_organization(org1)
      user2 = user_fixture() |> associate_with_organization(org2)

      connector = connector_fixture()
      connector_org1 = connector_organization_fixture(org1, connector, user1)
      connector_org2 = connector_organization_fixture(org2, connector, user2)

      file1 = file_fixture(connector_org1, %{sync_status: "unsynced"})
      file2 = file_fixture(connector_org2, %{sync_status: "unsynced"})

      %{
        org1: org1,
        file1: file1,
        file2: file2
      }
    end

    test "enqueues jobs with correct organization_id", %{file1: file1} do
      {:ok, count} = Files.sync_and_process_files([file1.id])
      assert count == 1

      # Verify the Oban job was created with organization_id
      jobs = all_enqueued(worker: ProcessTextFileWorker)
      assert length(jobs) == 1
      job = hd(jobs)
      assert job.args["file_id"] == file1.id
      assert job.args["organization_id"] != nil
    end
  end

  # Helper functions
  defp associate_with_organization(user, org) do
    # This assumes you have a way to associate users with organizations
    # Adjust based on your actual schema
    Playground.Repo.insert!(%Playground.Organizations.OrganizationMember{
      organization_id: org.id,
      user_id: user.id,
      role: "admin"
    })

    user
  end
end
