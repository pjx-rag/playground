defmodule Playground.AI do
  @moduledoc """
  The AI context for managing chat conversations and messages.

  Provides functions for:
  - Creating and managing chats
  - Sending messages and enqueueing AI responses
  - Rate limiting per user
  - Admin oversight (viewing all users' chats)
  - Cost tracking and analytics
  """

  import Ecto.Query, warn: false
  alias Playground.Repo
  alias Playground.AI.{Chat, Message, RequestTracking}
  alias Playground.Accounts.User
  alias Playground.Authorization
  alias Playground.Settings

  # ============================================================================
  # Chat Functions
  # ============================================================================

  @doc """
  Returns the list of chats for a user, with admin override support.

  ## Parameters
    - user_id: ID of the user whose chats to fetch
    - current_user: The user making the request (for authorization)

  ## Examples

      iex> list_user_chats(user_id, current_user)
      [%Chat{}, ...]

  """
  def list_user_chats(user_id, %User{} = current_user) do
    cond do
      # User viewing their own chats
      current_user.id == user_id ->
        from(c in Chat,
          where: c.user_id == ^user_id,
          order_by: [desc: c.updated_at]
        )
        |> Repo.all()

      # Admin viewing another user's chats
      Authorization.can?(current_user, "ai_chat:view_all") ->
        from(c in Chat,
          where: c.user_id == ^user_id,
          order_by: [desc: c.updated_at],
          preload: [:user]
        )
        |> Repo.all()

      # Unauthorized
      true ->
        []
    end
  end

  @doc """
  Returns all chats across all users (admin only).
  """
  def list_all_chats(%User{} = current_user) do
    if Authorization.can?(current_user, "ai_chat:view_all") do
      from(c in Chat,
        order_by: [desc: c.updated_at],
        preload: [:user]
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Gets a single chat with authorization check.

  Raises `Ecto.NoResultsError` if the Chat does not exist or user is not authorized.
  """
  def get_chat!(id, user_id) do
    from(c in Chat,
      where: c.id == ^id and c.user_id == ^user_id,
      preload: [:user]
    )
    |> Repo.one!()
  end

  @doc """
  Gets a single chat for admin viewing (no user_id check).
  """
  def get_chat_for_admin!(id, %User{} = admin) do
    if Authorization.can?(admin, "ai_chat:view_all") do
      Repo.get!(Chat, id) |> Repo.preload(:user)
    else
      raise Ecto.NoResultsError, queryable: Chat
    end
  end

  @doc """
  Creates a chat.

  ## Examples

      iex> create_chat(user, %{title: "New conversation", model: "gpt-4"})
      {:ok, %Chat{}}

      iex> create_chat(user, %{title: nil})
      {:error, %Ecto.Changeset{}}

  """
  def create_chat(%User{} = user, attrs \\ %{}) do
    %Chat{user_id: user.id}
    |> Chat.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a chat with the given attributes.

  ## Examples

      iex> update_chat(chat, %{title: "Updated Title"})
      {:ok, %Chat{}}

      iex> update_chat(chat, %{title: nil})
      {:error, %Ecto.Changeset{}}

  """
  def update_chat(%Chat{} = chat, attrs) do
    chat
    |> Chat.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a chat (cascades to messages).
  """
  def delete_chat(%Chat{} = chat, %User{} = user) do
    # Verify ownership or admin
    if chat.user_id == user.id or Authorization.can?(user, "ai_chat:view_all") do
      Repo.delete(chat)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking chat changes.
  """
  def change_chat(%Chat{} = chat, attrs \\ %{}) do
    Chat.changeset(chat, attrs)
  end

  @doc """
  Auto-generates a chat title from the first user message.
  Takes the first 50 characters of the first message.
  """
  def auto_generate_chat_title(%Chat{} = chat) do
    first_message =
      from(m in Message,
        where: m.chat_id == ^chat.id and m.role == "user",
        order_by: [asc: m.inserted_at],
        limit: 1
      )
      |> Repo.one()

    if first_message do
      title =
        first_message.content
        |> String.slice(0, 50)
        |> String.trim()
        |> then(fn s -> if String.length(first_message.content) > 50, do: s <> "...", else: s end)

      update_chat(chat, %{title: title})
    else
      {:ok, chat}
    end
  end

  # ============================================================================
  # Message Functions
  # ============================================================================

  @doc """
  Lists messages for a chat with optional pagination.

  ## Options
    - limit: Maximum number of messages to return (default: 100)
    - offset: Number of messages to skip (default: 0)
  """
  def list_messages(chat_id, opts \\ []) do
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
          case record_request(chat.user_id) do
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
  """
  def create_assistant_message(
        %Chat{} = chat,
        content,
        tokens_used,
        cost_usd,
        api_request_log_id
      ) do
    message_attrs = %{
      chat_id: chat.id,
      role: "assistant",
      content: content,
      tokens_used: tokens_used,
      cost_usd: cost_usd,
      api_request_log_id: api_request_log_id
    }

    with {:ok, message} <- %Message{} |> Message.changeset(message_attrs) |> Repo.insert(),
         {:ok, _chat} <- update_chat(chat, %{is_processing: false}) do
      {:ok, message}
    end
  end

  defp enqueue_ai_response(%Chat{} = chat, %Message{} = user_message) do
    %{
      chat_id: chat.id,
      user_id: chat.user_id,
      user_message_id: user_message.id,
      user_message: user_message.content
    }
    |> Playground.Workers.AIChatWorker.new(queue: :ai_chat)
    |> Oban.insert()
  end

  @doc """
  Clears the is_processing flag on a chat.

  Used by the worker to reset state on error or cancellation.

  ## Examples

      iex> clear_processing_flag(chat)
      {:ok, %Chat{is_processing: false}}

  """
  def clear_processing_flag(%Chat{} = chat) do
    update_chat(chat, %{is_processing: false})
  end

  # ============================================================================
  # Rate Limiting
  # ============================================================================

  @doc """
  Checks if a user has exceeded their rate limits across multiple time windows.

  Returns {:ok, stats} if under all limits, {:error, {:rate_limit_exceeded, window}} if over.

  Uses a single optimized database query with FILTER clauses for better performance.

  ## Examples

      iex> check_rate_limit(user_id)
      {:ok, %{per_minute: 18, per_hour: 95, per_day: 487}}

      iex> check_rate_limit(user_id)
      {:error, {:rate_limit_exceeded, :per_minute}}
  """
  def check_rate_limit(user_id) do
    now = DateTime.utc_now()
    settings = Settings.get_site_settings!()

    # Calculate time windows
    minute_ago = DateTime.add(now, -60, :second)
    hour_ago = DateTime.add(now, -1, :hour)
    day_ago = DateTime.add(now, -24, :hour)

    # Single query with FILTER clauses to count all windows at once
    counts =
      from(r in RequestTracking,
        where: r.user_id == ^user_id,
        select: %{
          per_minute:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^minute_ago),
          per_hour:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^hour_ago),
          per_day:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^day_ago)
        }
      )
      |> Repo.one()

    # Check each window
    windows = [
      {:per_minute, settings.ai_rate_limit_per_minute, counts.per_minute},
      {:per_hour, settings.ai_rate_limit_per_hour, counts.per_hour},
      {:per_day, settings.ai_rate_limit_per_day, counts.per_day}
    ]

    Enum.reduce_while(windows, {:ok, %{}}, fn {window_name, limit, count}, {:ok, stats} ->
      if count < limit do
        {:cont, {:ok, Map.put(stats, window_name, limit - count)}}
      else
        {:halt, {:error, {:rate_limit_exceeded, window_name}}}
      end
    end)
  end

  @doc """
  Records a new AI request timestamp for rate limiting.

  Note: Cleanup of old tracking records is handled by a scheduled Oban job
  to avoid performance impact during request processing.
  """
  def record_request(user_id) do
    now = DateTime.utc_now()

    # Insert new tracking record
    tracking_attrs = %{
      user_id: user_id,
      requested_at: now
    }

    %RequestTracking{}
    |> RequestTracking.changeset(tracking_attrs)
    |> Repo.insert()
  end

  @doc """
  Cleans up old request tracking records beyond the retention period (25 hours).

  This should be called by a scheduled Oban job, not synchronously during requests.
  Returns the number of records deleted.
  """
  def cleanup_old_request_tracking do
    cutoff = DateTime.add(DateTime.utc_now(), -25, :hour)

    {count, _} =
      from(r in RequestTracking,
        where: r.requested_at < ^cutoff
      )
      |> Repo.delete_all()

    count
  end

  @doc """
  Gets current usage stats for a user across all time windows.

  Returns %{
    per_minute: %{used: integer, limit: integer, remaining: integer},
    per_hour: %{used: integer, limit: integer, remaining: integer},
    per_day: %{used: integer, limit: integer, remaining: integer}
  }

  Uses a single optimized database query with FILTER clauses for better performance.
  """
  def get_usage_stats(user_id) do
    now = DateTime.utc_now()
    settings = Settings.get_site_settings!()

    # Calculate time windows
    minute_ago = DateTime.add(now, -60, :second)
    hour_ago = DateTime.add(now, -1, :hour)
    day_ago = DateTime.add(now, -24, :hour)

    # Single query with FILTER clauses to count all windows at once
    counts =
      from(r in RequestTracking,
        where: r.user_id == ^user_id,
        select: %{
          per_minute:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^minute_ago),
          per_hour:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^hour_ago),
          per_day:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^day_ago)
        }
      )
      |> Repo.one()

    # Build stats map
    %{
      per_minute: %{
        used: counts.per_minute,
        limit: settings.ai_rate_limit_per_minute,
        remaining: max(0, settings.ai_rate_limit_per_minute - counts.per_minute)
      },
      per_hour: %{
        used: counts.per_hour,
        limit: settings.ai_rate_limit_per_hour,
        remaining: max(0, settings.ai_rate_limit_per_hour - counts.per_hour)
      },
      per_day: %{
        used: counts.per_day,
        limit: settings.ai_rate_limit_per_day,
        remaining: max(0, settings.ai_rate_limit_per_day - counts.per_day)
      }
    }
  end

  # ============================================================================
  # Cost Tracking & Analytics
  # ============================================================================

  @doc """
  Calculates total cost for a user within a date range.

  ## Parameters
    - user_id: The user ID
    - date_range: Tuple of {start_date, end_date} or nil for all time

  ## Examples

      iex> get_total_cost_by_user(user_id, {~D[2024-01-01], ~D[2024-01-31]})
      Decimal.new("12.50")

  """
  def get_total_cost_by_user(user_id, date_range \\ nil) do
    query =
      from m in Message,
        join: c in Chat,
        on: m.chat_id == c.id,
        where: c.user_id == ^user_id and m.role == "assistant" and not is_nil(m.cost_usd),
        select: sum(m.cost_usd)

    query =
      case date_range do
        {start_date, end_date} ->
          from m in query,
            where: fragment("?::date", m.inserted_at) >= ^start_date,
            where: fragment("?::date", m.inserted_at) <= ^end_date

        nil ->
          query
      end

    Repo.one(query) || Decimal.new(0)
  end

  @doc """
  Calculates total cost for a specific chat.
  """
  def get_total_cost_by_chat(chat_id) do
    from(m in Message,
      where: m.chat_id == ^chat_id and m.role == "assistant" and not is_nil(m.cost_usd),
      select: sum(m.cost_usd)
    )
    |> Repo.one()
    |> then(fn sum -> sum || Decimal.new(0) end)
  end

  @doc """
  Gets message count and total cost for a chat.

  Uses a single optimized database aggregation query instead of loading
  all messages into memory.
  """
  def get_chat_stats(chat_id) do
    stats =
      from(m in Message,
        where: m.chat_id == ^chat_id,
        select: %{
          user_messages:
            fragment("COUNT(*) FILTER (WHERE role = 'user')"),
          assistant_messages:
            fragment("COUNT(*) FILTER (WHERE role = 'assistant')"),
          total_tokens: sum(m.tokens_used),
          total_cost: sum(m.cost_usd)
        }
      )
      |> Repo.one()

    %{
      user_messages: stats.user_messages,
      assistant_messages: stats.assistant_messages,
      total_tokens: stats.total_tokens || 0,
      total_cost: stats.total_cost || Decimal.new(0)
    }
  end
end
