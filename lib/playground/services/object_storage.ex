defmodule Playground.Services.ObjectStorage do
  @moduledoc """
  Service for interacting with S3-compatible object storage (Tigris, AWS S3, etc).
  """

  require Logger

  @doc """
  Uploads data to object storage and returns the public URL.
  """
  def upload(object_key, data, opts \\ []) do
    config = Application.get_env(:playground, :storage)
    bucket = opts[:bucket] || config[:bucket]

    Logger.info("Uploading to object storage: #{bucket}/#{object_key}")

    upload_opts = Keyword.merge(opts, acl: "public-read")

    case ExAws.S3.put_object(bucket, object_key, data, upload_opts)
         |> ExAws.request() do
      {:ok, _} ->
        url = build_url(bucket, object_key)
        {:ok, url}

      {:error, error} ->
        Logger.error("Failed to upload to object storage: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Downloads an object from storage.
  """
  def download(object_key, opts \\ []) do
    config = Application.get_env(:playground, :storage)
    bucket = opts[:bucket] || config[:bucket]

    Logger.info("Downloading from bucket: #{bucket}, key: #{object_key}")

    case ExAws.S3.get_object(bucket, object_key)
         |> ExAws.request() do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, error} ->
        Logger.error("Failed to download from storage: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Lists objects in a path.
  """
  def list_objects(prefix, opts \\ []) do
    config = Application.get_env(:playground, :storage)
    bucket = opts[:bucket] || config[:bucket]

    Logger.info("Listing objects with prefix: #{prefix} in bucket: #{bucket}")

    case ExAws.S3.list_objects(bucket, prefix: prefix)
         |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} when is_list(contents) ->
        {:ok, contents}

      {:ok, %{body: %{contents: nil}}} ->
        {:ok, []}

      {:ok, _response} ->
        {:ok, []}

      {:error, error} ->
        Logger.error("Failed to list objects: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Deletes an object from storage.
  """
  def delete(object_key, opts \\ []) do
    config = Application.get_env(:playground, :storage)
    bucket = opts[:bucket] || config[:bucket]

    Logger.info("Deleting object from storage: #{bucket}/#{object_key}")

    case ExAws.S3.delete_object(bucket, object_key)
         |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Successfully deleted object: #{object_key}")
        :ok

      {:error, error} ->
        Logger.error("Failed to delete object: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Generates a pre-signed URL for temporary access.
  """
  def presigned_url(object_key, opts \\ []) do
    config = Application.get_env(:playground, :storage)
    bucket = opts[:bucket] || config[:bucket]
    expires_in = opts[:expires_in] || 3600

    ExAws.Config.new(:s3)
    |> ExAws.S3.presigned_url(:get, bucket, object_key, expires_in: expires_in)
  end

  defp build_url(bucket, object_key) do
    clean_key = String.trim_leading(object_key, "/")
    "https://#{bucket}.fly.storage.tigris.dev/#{clean_key}"
  end
end
