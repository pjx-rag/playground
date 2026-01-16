defmodule Playground.Services.AI.OpenRouter do
  @moduledoc """
  OpenRouter API service for LLM chat completions with streaming support.

  OpenRouter provides unified access to multiple LLM providers (OpenAI, Anthropic,
  Google, Mistral, etc.) through a single API.

  ## Usage

      # Health check
      {:ok, %{status: :healthy}} = OpenRouter.health_check()

      # Stream chat completion
      {:ok, stream_response} = OpenRouter.stream_chat_completion(
        "mistralai/devstral-2512:free",
        [%{role: "user", content: "Hello!"}]
      )

      # Process streaming tokens
      stream_response.stream
      |> Stream.filter(&(&1.type == :content))
      |> Stream.map(& &1.text)
      |> Enum.each(&IO.write/1)

  ## Configuration

  Add to config/runtime.exs:

      config :playground, :openrouter,
        api_key: System.get_env("OPENROUTER_API_KEY"),
        base_url: "https://openrouter.ai/api/v1"

  """

  @behaviour Playground.Services.APIClient

  alias Playground.Services.ReqPlugins.APILogger
  require Logger

  @base_url "https://openrouter.ai/api/v1"

  # =============================================================================
  # APIClient Behaviour Implementation
  # =============================================================================

  @impl Playground.Services.APIClient
  def service_name, do: "openrouter"

  @impl Playground.Services.APIClient
  def base_url do
    Application.get_env(:playground, :openrouter)[:base_url] || @base_url
  end

  @impl Playground.Services.APIClient
  def health_check do
    start_time = System.monotonic_time(:millisecond)

    # Use the models endpoint for a lightweight health check (no streaming needed)
    case list_models() do
      {:ok, _models} ->
        latency = System.monotonic_time(:millisecond) - start_time

        {:ok,
         %{
           status: :healthy,
           latency_ms: latency,
           message: nil
         }}

      {:error, %{status: status}} when status in 400..499 ->
        # Client errors (like auth) still mean the service is up
        {:ok,
         %{
           status: :degraded,
           latency_ms: 0,
           message: "API returned status #{status} (check API key)"
         }}

      {:error, %{status: status}} ->
        {:ok,
         %{
           status: :unhealthy,
           latency_ms: 0,
           message: "API returned status #{status}"
         }}

      {:error, reason} ->
        {:ok,
         %{
           status: :unhealthy,
           latency_ms: 0,
           message: "Connection error: #{inspect(reason)}"
         }}
    end
  end

  @impl Playground.Services.APIClient
  def default_headers do
    api_key = api_key()

    # Note: The authorization header is automatically filtered by APILogger
    # to prevent API key exposure in logs and database. See ReqPlugins.APILogger.
    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"},
      {"http-referer", "https://playground.local"},
      {"x-title", "Playground AI Chat"}
    ]
  end

  @impl Playground.Services.APIClient
  def request_timeout, do: 60_000

  # =============================================================================
  # API Endpoints
  # =============================================================================

  @doc """
  Streams a chat completion from OpenRouter using ReqLLM.

  ## Parameters
    - model: Model ID (e.g., "mistralai/devstral-2512:free")
    - messages: List of message maps with :role and :content
    - opts: Optional parameters
      - max_tokens: Maximum tokens to generate
      - temperature: Sampling temperature (0.0-2.0)
      - top_p: Nucleus sampling parameter
      - stream: Enable streaming (default: true)

  ## Returns
    - `{:ok, %ReqLLM.StreamResponse{}}` - Stream response with .stream field
    - `{:error, reason}` - Error details

  ## Example

      {:ok, response} = OpenRouter.stream_chat_completion(
        "anthropic/claude-3.5-sonnet",
        [
          %{role: "system", content: "You are helpful."},
          %{role: "user", content: "Hello!"}
        ],
        temperature: 0.7
      )

      # Process stream
      response.stream
      |> Stream.filter(&(&1.type == :content))
      |> Stream.map(& &1.text)
      |> Enum.join("")

  """
  def stream_chat_completion(model, messages, opts \\ []) do
    model_spec = "openrouter:#{model}"
    stream_enabled = Keyword.get(opts, :stream, true)

    req_opts =
      opts
      |> Keyword.put(:api_key, api_key())
      |> Keyword.put(:base_url, base_url())
      |> Keyword.put(:stream, stream_enabled)
      |> Keyword.put(:headers, [
        {"http-referer", "https://playground.local"},
        {"x-title", "Playground AI Chat"}
      ])

    Logger.debug("OpenRouter request: model=#{model}, messages=#{length(messages)}")

    case ReqLLM.stream_text(model_spec, messages, req_opts) do
      {:ok, response} ->
        Logger.debug("OpenRouter stream started successfully")
        {:ok, response}

      {:error, reason} = error ->
        Logger.error("OpenRouter streaming failed: #{inspect(reason)}")
        error
    end
  rescue
    exception ->
      Logger.error("OpenRouter exception: #{inspect(exception)}")
      Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
      {:error, %{reason: exception, message: Exception.message(exception)}}
  end

  @doc """
  Non-streaming chat completion from OpenRouter using ReqLLM.

  Used by RAG agent pipeline for simple LLM calls (gate, decompose, rerank steps).

  ## Parameters
    - messages: List of message maps with :role and :content
    - opts: Optional parameters
      - model: Model ID (defaults to "anthropic/claude-3.5-haiku")
      - max_tokens: Maximum tokens to generate (defaults to 1000)
      - temperature: Sampling temperature (defaults to 0.0 for deterministic output)

  ## Returns
    - `{:ok, String.t()}` - The complete response text
    - `{:error, reason}` - Error details

  ## Example

      {:ok, answer} = OpenRouter.chat(
        [%{role: "user", content: "Is this a question about documents? Answer yes or no."}],
        model: "anthropic/claude-3.5-haiku"
      )
  """
  def chat(messages, opts \\ []) do
    model = Keyword.get(opts, :model, "anthropic/claude-3.5-haiku")
    max_tokens = Keyword.get(opts, :max_tokens, 1000)
    temperature = Keyword.get(opts, :temperature, 0.0)

    model_spec = "openrouter:#{model}"
    start_time = System.monotonic_time(:millisecond)

    req_opts = [
      temperature: temperature,
      max_tokens: max_tokens,
      provider_options: [
        app_referer: "https://playground.local",
        app_title: "Playground AI Chat"
      ]
    ]

    Logger.debug("OpenRouter chat request: model=#{model}, messages=#{length(messages)}")

    case ReqLLM.generate_text(model_spec, messages, req_opts) do
      {:ok, response} ->
        content = ReqLLM.Response.text(response) || ""
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # Log API call with usage/cost info
        log_api_call(model, messages, response, duration_ms, true)

        Logger.debug("OpenRouter chat completed: #{String.length(content)} chars")
        {:ok, content}

      {:error, reason} = error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        log_api_error(model, messages, reason, duration_ms)

        Logger.error("OpenRouter chat failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Lists available models from OpenRouter.

  Returns a list of models with their capabilities and pricing.

  ## Example

      {:ok, models} = OpenRouter.list_models()

  """
  def list_models do
    req()
    |> Req.get(url: "/models")
    |> normalize_response()
  end

  @doc """
  Gets information about a specific model.

  ## Example

      {:ok, model_info} = OpenRouter.get_model("anthropic/claude-3.5-sonnet")

  """
  def get_model(model_id) do
    req()
    |> Req.get(url: "/models/#{model_id}")
    |> normalize_response()
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp req do
    Req.new(
      base_url: base_url(),
      headers: default_headers(),
      receive_timeout: request_timeout(),
      # Retry transient errors (5xx, network errors) up to 3 times
      retry: :transient,
      max_retries: 3,
      retry_delay: fn attempt -> 1000 * attempt end
    )
    |> APILogger.attach(service: service_name())
  end

  defp api_key do
    case Application.get_env(:playground, :openrouter)[:api_key] do
      nil ->
        raise "OPENROUTER_API_KEY not configured. Please set the environment variable."

      "" ->
        raise "OPENROUTER_API_KEY is empty. Please provide a valid API key."

      key ->
        key
    end
  end

  defp normalize_response({:ok, %Req.Response{status: status, body: body, headers: headers}})
       when status in 200..299 do
    {:ok, %{status: status, body: body, headers: headers}}
  end

  defp normalize_response({:ok, %Req.Response{status: status, body: body, headers: headers}}) do
    {:error, %{status: status, body: body, headers: headers}}
  end

  defp normalize_response({:error, exception}) do
    {:error, %{reason: exception, message: Exception.message(exception)}}
  end

  # =============================================================================
  # API Logging
  # =============================================================================

  defp log_api_call(model, messages, response, duration_ms, success) do
    usage = response.usage || %{}

    log_data = %{
      service: service_name(),
      method: "POST",
      path: "/chat/completions",
      url: "#{base_url()}/chat/completions",
      status_code: "200",
      duration_ms: duration_ms,
      success: success,
      request_headers: %{"content-type" => "application/json"},
      request_body: Jason.encode!(%{model: model, messages: format_messages_for_log(messages)}),
      response_body: Jason.encode!(%{
        model: model,
        usage: usage,
        content_length: String.length(ReqLLM.Response.text(response) || "")
      }),
      cost_usd: Decimal.from_float(usage[:total_cost] || 0.0),
      tokens_prompt: usage[:input_tokens],
      tokens_completion: usage[:output_tokens],
      tokens_total: usage[:total_tokens],
      metadata: %{
        model: model,
        cached_tokens: usage[:cached_tokens],
        reasoning_tokens: usage[:reasoning_tokens]
      }
    }

    persist_log(log_data)
  end

  defp log_api_error(model, messages, reason, duration_ms) do
    log_data = %{
      service: service_name(),
      method: "POST",
      path: "/chat/completions",
      url: "#{base_url()}/chat/completions",
      status_code: "error",
      duration_ms: duration_ms,
      success: false,
      request_headers: %{"content-type" => "application/json"},
      request_body: Jason.encode!(%{model: model, messages: format_messages_for_log(messages)}),
      error_message: inspect(reason)
    }

    persist_log(log_data)
  end

  defp format_messages_for_log(messages) do
    # Store full message content for complete API request logs
    Enum.map(messages, fn msg ->
      content = msg[:content] || msg["content"] || ""
      %{role: msg[:role] || msg["role"], content: content}
    end)
  end

  defp persist_log(log_data) do
    Task.start(fn ->
      try do
        %Playground.Services.APIRequestLog{}
        |> Playground.Services.APIRequestLog.changeset(log_data)
        |> Playground.Repo.insert()
      rescue
        e ->
          Logger.warning("Failed to persist API request log: #{inspect(e)}")
      end
    end)
  end
end
