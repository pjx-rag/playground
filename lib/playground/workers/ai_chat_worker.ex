defmodule Playground.Workers.AIChatWorker do
  @moduledoc """
  Oban worker for processing AI chat requests with streaming responses.

  Responsibilities:
  - Fetch chat and message history
  - Build OpenRouter API request with markdown system prompt
  - Stream tokens via PubSub for real-time UI updates
  - Track costs and link to API request logs
  - Handle errors and reset chat processing state
  """

  use Oban.Worker, queue: :ai_chat, max_attempts: 1

  alias Playground.AI
  alias Playground.PubSub
  alias Playground.Services.OpenRouter

  require Logger

  # Maximum number of messages to include in conversation context
  @max_context_messages 100
  
  # Timeout for stream processing (5 minutes)
  @stream_timeout_ms 300_000

  @system_prompt """
  You are a helpful AI assistant. Always format your responses using Markdown for better readability.
  Use headings, lists, code blocks, and other Markdown features to structure your responses clearly.
  """

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "chat_id" => chat_id,
          "user_id" => user_id,
          "user_message_id" => _user_message_id,
          "user_message" => _user_message
        }
      }) do
    # Broadcast streaming start
    broadcast_event(user_id, chat_id, :streaming_start)

    # Fetch chat and message history
    chat = AI.get_chat!(chat_id, user_id)
    messages = AI.list_messages(chat_id, limit: @max_context_messages)

    # Build message history for API
    message_history = build_message_history(messages)

    # Make streaming API request
    case stream_ai_response(chat, message_history, user_id) do
      {:ok, assistant_message} ->
        broadcast_event(user_id, chat_id, {:message_completed, assistant_message})
        :ok

      {:error, reason} ->
        Logger.error("AI chat worker failed: #{inspect(reason)}")

        # Create error message for user
        error_content = """
        I apologize, but I'm currently unable to process your request. The AI chat service is temporarily unavailable.

        Please try again in a few moments. If the problem persists, please contact support.
        """

        # Try to save error message as assistant response
        case AI.create_assistant_message(chat, error_content, 0, Decimal.new(0), nil) do
          {:ok, error_message} ->
            # Successfully saved error message, broadcast completion
            broadcast_event(user_id, chat_id, {:message_completed, error_message})

          {:error, save_error} ->
            # Failed to save error message, clear processing flag and broadcast error
            Logger.error("Failed to save error message: #{inspect(save_error)}")
            AI.clear_processing_flag(chat)
            # Broadcast both message_failed and error events to ensure UI gets notified
            broadcast_event(user_id, chat_id, {:message_failed, reason})
            broadcast_event(user_id, chat_id, {:error, "Failed to process your request"})
        end

        {:error, reason}
    end
  end

  defp build_message_history(messages) do
    [%{role: "system", content: @system_prompt}] ++
      Enum.map(messages, fn msg ->
        %{role: msg.role, content: msg.content}
      end)
  end

  defp stream_ai_response(chat, message_history, user_id) do
    Logger.info("Streaming AI response: model=#{chat.model}, messages=#{length(message_history)}")

    # Use OpenRouter service for streaming
    case OpenRouter.stream_chat_completion(chat.model, message_history) do
      {:ok, response} ->
        Logger.info("Stream started successfully")

        # Stream tokens and accumulate content with timeout protection
        task = Task.async(fn ->
          response.stream
          |> Stream.filter(fn chunk -> chunk.type == :content end)
          |> Stream.map(fn chunk ->
            text = chunk.text || ""
            Logger.debug("Received chunk: #{text}")

            # Broadcast token chunk via PubSub for real-time UI updates
            if text != "" do
              broadcast_event(user_id, chat.id, {:token_chunk, text})
            end

            text
          end)
          |> Enum.join("")
        end)

        accumulated_content = 
          case Task.yield(task, @stream_timeout_ms) || Task.shutdown(task) do
            {:ok, content} ->
              Logger.info("Streaming completed, total content length: #{String.length(content)}")
              content
            
            nil ->
              Logger.error("Stream processing timed out after #{@stream_timeout_ms}ms")
              raise "Stream processing timed out"
          end

        # Extract token usage and cost from ReqLLM response
        # ReqLLM provides usage metadata in response.usage with token counts and USD costs
        # Note: response.usage may be nil if the stream hasn't been fully consumed
        usage = Map.get(response, :usage, %{})
        tokens_used = Map.get(usage, :total_tokens, 0)

        cost_usd =
          case Map.get(usage, :total_cost) do
            cost when is_number(cost) -> 
              # Convert float to Decimal with proper rounding for currency (6 decimal places for micro-cents)
              cost 
              |> Decimal.from_float() 
              |> Decimal.round(6)
            _ -> 
              Decimal.new(0)
          end

        Logger.info("Token usage: #{tokens_used}, Cost: $#{cost_usd}")

        # TODO: Link to API request log when APILogger integration is available
        api_log_id = nil

        # Save assistant message with cost tracking
        case AI.create_assistant_message(
               chat,
               accumulated_content,
               tokens_used,
               cost_usd,
               api_log_id
             ) do
          {:ok, message} ->
            {:ok, message}

          {:error, reason} ->
            Logger.error("Failed to save assistant message: #{inspect(reason)}")
            AI.clear_processing_flag(chat)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("OpenRouter streaming failed: #{inspect(reason, pretty: true)}")
        broadcast_event(user_id, chat.id, {:error, "Failed to generate response"})
        {:error, reason}
    end
  end

  defp broadcast_event(user_id, chat_id, event) do
    Phoenix.PubSub.broadcast(
      PubSub,
      "ai_chat:#{user_id}:#{chat_id}",
      event
    )
  end
end
