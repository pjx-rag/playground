defmodule Playground.Workers.AIChatWorker do
  @moduledoc """
  Oban worker for processing AI chat requests with streaming responses and RAG integration.

  Responsibilities:
  - Fetch chat and message history
  - Execute RAG pipeline to retrieve relevant context from knowledge base
  - Build OpenRouter API request with RAG-enhanced system prompt
  - Stream tokens via PubSub for real-time UI updates
  - Track costs, RAG metadata, and link to API request logs
  - Handle errors and reset chat processing state

  ## RAG Integration Flow

  1. Extract user question from message history
  2. Execute RAG pipeline (gate → decompose → search → rerank → reason → answer)
  3. If retrieval needed and citations found, enhance system prompt with context
  4. Stream AI response with injected knowledge base context
  5. Save RAG metadata (mode, chunks used, citations) in assistant message
  """

  use Oban.Worker, queue: :ai_chat, max_attempts: 1

  alias Playground.AI
  alias Playground.PubSub
  alias Playground.RAG.Pipeline
  alias Playground.Services.OpenRouter

  require Logger

  # Maximum number of messages to include in conversation context
  @max_context_messages 100
  
  # Timeout for stream processing (5 minutes)
  @stream_timeout_ms 300_000

  @system_prompt """
  You are a helpful AI assistant with access to a knowledge base. Always format your responses using Markdown for better readability.
  Use headings, lists, code blocks, and other Markdown features to structure your responses clearly.

  When answering questions about specific documents or data:
  - If you don't have access to specific information, clearly state that you cannot access that information
  - Never make up specific details like names, numbers, or dates
  - Be honest about the limitations of your knowledge
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
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Streaming AI response: model=#{chat.model}, messages=#{length(message_history)}")

    # Extract user's question from last message
    user_question =
      message_history
      |> Enum.reverse()
      |> Enum.find(fn msg -> msg.role == "user" end)
      |> case do
        nil -> ""
        msg -> msg.content
      end

    # Execute RAG pipeline to get relevant context
    # TODO: Get organization_id from user association when available
    organization_id = 1  # Default PJX organization

    Logger.info("Executing RAG pipeline", question: user_question, organization_id: organization_id)

    # Execute RAG pipeline with timeout (30 seconds)
    rag_task = Task.async(fn -> Pipeline.run(user_question, organization_id) end)

    rag_context =
      case Task.yield(rag_task, 30_000) || Task.shutdown(rag_task) do
        {:ok, {:ok, ctx}} ->
          # Check if retrieval was skipped (needs_retrieval is false or nil)
          skip_retrieval = !ctx.needs_retrieval

          Logger.info("RAG pipeline completed",
            needs_retrieval: ctx.needs_retrieval,
            skip_retrieval: skip_retrieval,
            citations_count: length(ctx.citations || [])
          )
          ctx

        {:ok, {:error, reason}} ->
          Logger.error("RAG pipeline failed: #{inspect(reason)}")
          nil

        nil ->
          Logger.error("RAG pipeline timed out after 30 seconds")
          nil
      end

    # Build enhanced message history with RAG context if available
    # Only enhance if retrieval was not explicitly skipped AND citations were found
    # In simple RAG mode, needs_retrieval is nil (gate step not run), so we proceed
    # In agentic RAG mode, needs_retrieval is true/false based on gate decision
    {enhanced_message_history, numbered_chunks} =
      if rag_context && rag_context.needs_retrieval != false && length(rag_context.citations || []) > 0 do
        Logger.info("Enhancing prompt with #{length(rag_context.citations)} citations")
        build_message_history_with_context(message_history, rag_context)
      else
        Logger.info("No RAG context to inject, using standard message history",
          needs_retrieval: rag_context && rag_context.needs_retrieval,
          citations_count: rag_context && length(rag_context.citations || [])
        )
        {message_history, []}
      end

    # Build AI options from chat settings
    ai_opts = [
      temperature: chat.temperature,
      max_tokens: chat.max_tokens,
      top_p: chat.top_p,
      frequency_penalty: chat.frequency_penalty,
      presence_penalty: chat.presence_penalty
    ]

    Logger.debug("AI options: #{inspect(ai_opts)}")

    # Use OpenRouter service for streaming with chat-specific settings
    case OpenRouter.stream_chat_completion(chat.model, enhanced_message_history, ai_opts) do
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
        # ReqLLM collects usage metadata concurrently during streaming
        # Must call StreamResponse.usage/1 after stream consumption to get the data
        usage = ReqLLM.StreamResponse.usage(response) || %{}
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

        # Log API request with usage/cost info
        api_log_id = log_streaming_api_call(
          chat.model,
          enhanced_message_history,
          usage,
          accumulated_content,
          System.monotonic_time(:millisecond) - start_time
        )

        # Build RAG metadata from context with numbered chunks for citation display
        rag_attrs = build_rag_attrs(rag_context, numbered_chunks)

        # Save assistant message with cost tracking and RAG metadata
        case AI.create_assistant_message(
               chat,
               accumulated_content,
               tokens_used,
               cost_usd,
               api_log_id,
               rag_attrs
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

  defp build_message_history_with_context(message_history, rag_context) do
    # Build context section from ranked chunks (agentic RAG) or search results (simple RAG)
    # In simple RAG mode, ranked_chunks is nil since rerank step doesn't run
    chunks = rag_context.ranked_chunks || rag_context.search_results || []

    # Take top chunks ordered by relevance score, number them [1], [2], etc.
    numbered_chunks =
      chunks
      |> Enum.take(10)
      |> Enum.with_index(1)

    context_section =
      numbered_chunks
      |> Enum.map(fn {result, index} ->
        content = String.trim(result.chunk.content)

        """
        [#{index}]

        #{content}
        """
      end)
      |> Enum.join("\n\n---\n\n")

    # Enhanced system prompt with RAG context and citation instructions
    enhanced_system_prompt = """
    You are a helpful AI assistant with access to a knowledge base. Always format your responses using Markdown for better readability.
    Use headings, lists, code blocks, and other Markdown features to structure your responses clearly.

    # Retrieved Context

    #{context_section}

    # Critical Instructions

    - **ONLY use information from the context provided above**
    - **DO NOT make up or infer information that isn't explicitly stated in the context**
    - **When using information from the context, cite the source using the bracket notation like [1], [2], etc.**
    - You can cite multiple sources in one statement: "The property was inspected [1] and the contract was signed [3]"
    - If the context doesn't contain the information needed to answer the question, explicitly state: "The provided context does not contain information about [specific detail]"
    - Never say "I don't have access to" or similar phrases - you DO have access to the context above
    - Be concise but thorough in your response
    """

    # Replace the system prompt in message history
    enhanced_history =
      message_history
      |> Enum.map(fn msg ->
        if msg.role == "system" do
          %{msg | content: enhanced_system_prompt}
        else
          msg
        end
      end)

    # Return both the enhanced history and the numbered chunks for citation storage
    {enhanced_history, numbered_chunks}
  end

  defp build_rag_attrs(nil, _numbered_chunks), do: %{}

  defp build_rag_attrs(rag_context, numbered_chunks) do
    # Extract RAG mode from metadata steps (check if gate step exists)
    rag_mode =
      if Enum.any?(rag_context.metadata.steps, &(&1.step == :gate)) do
        "agentic_rag"
      else
        "rag"
      end

    # Extract reason iterations from metadata steps
    reason_steps = Enum.filter(rag_context.metadata.steps, &(&1.step == :reason))
    reason_iterations = length(reason_steps)

    # Build citations from numbered chunks (includes position numbers for UI display)
    citations = build_numbered_citations(numbered_chunks)

    %{
      rag_mode: rag_mode,
      skip_retrieval: !rag_context.needs_retrieval,
      needs_retrieval: rag_context.needs_retrieval,
      context_sufficient: rag_context.context_sufficient,
      reason_iterations: reason_iterations,
      sub_questions: rag_context.sub_questions || [],
      num_chunks_retrieved: length(rag_context.ranked_chunks || rag_context.search_results || []),
      chunks_used: length(numbered_chunks),
      rag_debug_data: %{
        metadata: rag_context.metadata || %{},
        citations: citations
      }
    }
  end

  # Build citations with position numbers from the numbered chunks sent to the LLM
  defp build_numbered_citations(numbered_chunks) do
    Enum.map(numbered_chunks, fn {result, position} ->
      %{
        position: position,
        file_id: result.file.id,
        file_name: result.file.name,
        file_url: get_file_url(result.file),
        chunk_id: result.chunk.id,
        semantic_score: result.semantic_score,
        hybrid_score: result.hybrid_score,
        rerank_score: Map.get(result, :rerank_score)
      }
    end)
  end

  # Extract URL from file metadata (Google Drive web_view_link, etc.)
  defp get_file_url(file) do
    metadata = file.metadata || %{}

    cond do
      Map.get(metadata, "web_view_link") -> Map.get(metadata, "web_view_link")
      Map.get(metadata, "webViewLink") -> Map.get(metadata, "webViewLink")
      true -> nil
    end
  end

  defp broadcast_event(user_id, chat_id, event) do
    Phoenix.PubSub.broadcast(
      PubSub,
      "ai_chat:#{user_id}:#{chat_id}",
      event
    )
  end

  defp log_streaming_api_call(model, messages, usage, response_content, duration_ms) do
    log_data = %{
      service: "openrouter",
      method: "POST",
      path: "/chat/completions",
      url: "https://openrouter.ai/api/v1/chat/completions",
      status_code: "200",
      duration_ms: duration_ms,
      success: true,
      request_headers: %{"content-type" => "application/json"},
      request_body: Jason.encode!(%{model: model, messages: format_messages_for_log(messages), stream: true}),
      response_body: Jason.encode!(%{
        model: model,
        usage: usage,
        content_length: String.length(response_content)
      }),
      cost_usd: if(usage[:total_cost], do: Decimal.from_float(usage[:total_cost]), else: nil),
      tokens_prompt: usage[:input_tokens],
      tokens_completion: usage[:output_tokens],
      tokens_total: usage[:total_tokens],
      metadata: %{
        model: model,
        streaming: true,
        cached_tokens: usage[:cached_tokens],
        reasoning_tokens: usage[:reasoning_tokens]
      }
    }

    # Insert synchronously to get the ID
    case Playground.Repo.insert(Playground.APIRequestLog.changeset(%Playground.APIRequestLog{}, log_data)) do
      {:ok, log} -> log.id
      {:error, _reason} -> nil
    end
  end

  defp format_messages_for_log(messages) do
    # Store full message content for complete API request logs
    Enum.map(messages, fn msg ->
      content = msg[:content] || msg["content"] || ""
      %{role: msg[:role] || msg["role"], content: content}
    end)
  end
end
