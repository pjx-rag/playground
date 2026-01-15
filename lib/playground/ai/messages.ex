defmodule Playground.AI.Messages do
  @moduledoc """
  Message management operations.

  Used by:
  - AIChatLive
  - AdminAIChatLive.Show
  - AIChatWorker
  """

  import Ecto.Query, warn: false
  alias Playground.Repo
  alias Playground.AI.{Chat, Message}
  alias Playground.Workers.AIChatWorker

  @doc """
  Lists messages for a chat with optional pagination.

  ## Options
    - limit: Maximum number of messages to return (default: 100)
    - offset: Number of messages to skip (default: 0)

  Used by: AIChatLive, AdminAIChatLive.Show
  """
  def list_for_chat(chat_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    from(m in Message,
      where: m.chat_id == ^chat_id,
      order_by: [asc: m.inserted_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Creates a user message and enqueues an AI response job.

  Also records the request for rate limiting purposes.
  Returns {:error, :chat_is_processing} if the chat is already processing a message.

  Uses optimistic locking and a transaction to prevent race conditions and ensure
  all operations succeed or fail together.

  ## Examples

      iex> create_user_message(chat, "Hello, how are you?")
      {:ok, %Message{}}

      iex> create_user_message(chat, "Second message before first completes")
      {:error, :chat_is_processing}

  Used by: AIChatLive
  """
  def create_user_message(%Chat{} = chat, content) when is_binary(content) do
    # Use a transaction to ensure atomicity
    Repo.transaction(fn ->
      # Optimistically lock the chat and set is_processing to true atomically
      # This prevents race conditions where two requests try to process simultaneously
      {updated_count, _} =
        from(c in Chat,
          where: c.id == ^chat.id and c.is_processing == false,
          select: c
        )
        |> Repo.update_all(set: [is_processing: true, updated_at: DateTime.utc_now()])

      case updated_count do
        0 ->
          # Chat was already processing or doesn't exist
          Repo.rollback(:chat_is_processing)

        1 ->
          # Successfully locked the chat, proceed with message creation
          message_attrs = %{
            chat_id: chat.id,
            role: "user",
            content: String.trim(content)
          }

          # Create user message
          message =
            case %Message{} |> Message.changeset(message_attrs) |> Repo.insert() do
              {:ok, msg} -> msg
              {:error, changeset} -> Repo.rollback(changeset)
            end

          # Record request for rate limiting
          case Playground.AI.RateLimiting.record_request(chat.user_id) do
            {:ok, _tracking} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end

          # Reload chat to get updated version
          updated_chat = Repo.get!(Chat, chat.id)

          # Enqueue AI response job
          case enqueue_ai_response(updated_chat, message) do
            {:ok, _job} -> message
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
    |> case do
      {:ok, message} -> {:ok, message}
      {:error, :chat_is_processing} -> {:error, :chat_is_processing}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Creates an assistant message with cost tracking.

  Called by the AIChatWorker after receiving AI response.
  Clears the is_processing flag to allow new messages.

  Used by: AIChatWorker
  """
  def create_assistant_message(
        %Chat{} = chat,
        content,
        tokens_used,
        cost_usd,
        api_request_log_id,
        rag_attrs \\ %{}
      ) do
    message_attrs =
      %{
        chat_id: chat.id,
        role: "assistant",
        content: content,
        tokens_used: tokens_used,
        cost_usd: cost_usd,
        api_request_log_id: api_request_log_id
      }
      |> Map.merge(rag_attrs)

    with {:ok, message} <- %Message{} |> Message.changeset(message_attrs) |> Repo.insert(),
         {:ok, _chat} <- Playground.AI.Chats.update(chat, %{is_processing: false}) do
      {:ok, message}
    end
  end

  # Private functions

  defp enqueue_ai_response(%Chat{} = chat, %Message{} = user_message) do
    %{
      chat_id: chat.id,
      user_id: chat.user_id,
      user_message_id: user_message.id,
      user_message: user_message.content
    }
    |> AIChatWorker.new(queue: :ai_chat)
    |> Oban.insert()
  end

  @doc """
  Gets the first user message for a chat.

  Used by: Chats.auto_generate_title/1
  """
  def get_first_user_message(chat_id) do
    from(m in Message,
      where: m.chat_id == ^chat_id and m.role == "user",
      order_by: [asc: m.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end
end
