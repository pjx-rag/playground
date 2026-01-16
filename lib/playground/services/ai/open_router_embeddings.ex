defmodule Playground.Services.AI.OpenRouterEmbeddings do
  @moduledoc """
  Client for OpenRouter Embeddings API.

  Generates embeddings for text chunks using OpenAI's embedding models via OpenRouter.

  Note: Uses raw Req instead of ReqLLM because OpenRouter embedding models
  are not in LLMDB registry. ReqLLM requires models to be registered.

  ## Configuration

  The embedding model and dimensions are configured via app settings:
  - `embedding_model`: e.g., "text-embedding-3-small" (default)
  - `embedding_dimensions`: e.g., "1536" (default, matches database schema)

  ## Usage

      # Generate embeddings for a list of text strings
      texts = ["hello world", "foo bar"]
      {:ok, embeddings} = OpenRouterEmbeddings.create_embeddings(texts)

      # embeddings is a list of vectors matching the order of texts
      [
        [0.1, 0.2, ...],  # 1536 dimensions for text-embedding-3-small
        [0.3, 0.4, ...]
      ]

  ## Rate Limits

  OpenRouter has rate limits. This module handles batching internally.
  For large volumes, consider using smaller batch sizes or delays between requests.
  """

  require Logger
  alias Playground.Settings

  @api_base "https://openrouter.ai/api/v1"
  @max_batch_size 100

  @doc """
  Creates embeddings for a list of text strings.

  ## Parameters

  - `texts`: List of strings to embed (max #{@max_batch_size} per request)

  ## Returns

  - `{:ok, embeddings}` where embeddings is a list of float lists
  - `{:error, reason}` on failure

  ## Examples

      iex> create_embeddings(["hello", "world"])
      {:ok, [[0.1, 0.2, ...], [0.3, 0.4, ...]]}

      iex> create_embeddings([])
      {:error, :empty_texts}
  """
  def create_embeddings([]), do: {:error, :empty_texts}

  def create_embeddings(texts) when is_list(texts) do
    if length(texts) > @max_batch_size do
      {:error, {:batch_too_large, @max_batch_size}}
    else
      do_create_embeddings(texts)
    end
  end

  defp do_create_embeddings(texts) do
    # Get configuration from app settings
    model = Settings.get_app_setting_value("embedding_model", "text-embedding-3-small")
    dimensions = Settings.get_app_setting_value("embedding_dimensions", "1536")

    # Get API key from environment
    api_key = System.get_env("OPENROUTER_API_KEY")

    if api_key do
      url = "#{@api_base}/embeddings"

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        model: model,
        input: texts,
        dimensions: String.to_integer(dimensions)
      }

      Logger.debug("Creating embeddings: model=#{model}, texts=#{length(texts)}")

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          embeddings =
            response
            |> Map.get("data", [])
            |> Enum.map(fn item -> Map.get(item, "embedding") end)

          Logger.debug("Embeddings created: #{length(embeddings)} vectors")
          {:ok, embeddings}

        {:ok, %{status: status, body: body}} ->
          Logger.error("OpenRouter API error", status: status, body: inspect(body))
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          Logger.error("OpenRouter API request failed", reason: inspect(reason))
          {:error, {:request_failed, reason}}
      end
    else
      Logger.error("OPENROUTER_API_KEY environment variable not set")
      {:error, :missing_api_key}
    end
  end

  @doc """
  Batch creates embeddings for a large list of texts.

  Automatically splits into batches of #{@max_batch_size} and processes sequentially.
  Returns embeddings in the same order as input texts.

  ## Parameters

  - `texts`: List of strings to embed (any size)
  - `opts`: Options
    - `:delay_ms` - Milliseconds to wait between batches (default: 100)

  ## Returns

  - `{:ok, embeddings}` where embeddings is a list of float lists
  - `{:error, reason}` on failure

  ## Examples

      iex> batch_create_embeddings(["text1", "text2", ...], delay_ms: 200)
      {:ok, [[0.1, ...], [0.2, ...], ...]}
  """
  def batch_create_embeddings(texts, opts \\ []) when is_list(texts) do
    delay_ms = Keyword.get(opts, :delay_ms, 100)

    texts
    |> Enum.chunk_every(@max_batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      case create_embeddings(batch) do
        {:ok, embeddings} ->
          # Add delay between batches to respect rate limits
          if delay_ms > 0, do: Process.sleep(delay_ms)
          {:cont, {:ok, acc ++ embeddings}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
