defmodule Playground.AI.Analytics do
  @moduledoc """
  Cost tracking and analytics operations for AI chats.

  Used by:
  - AdminAIChatLive.Index (user cost summaries)
  - AdminAIChatLive.Show (chat cost details)
  - AIChatLive (chat statistics)
  """

  import Ecto.Query, warn: false
  alias Playground.Repo
  alias Playground.AI.{Chat, Message}

  @doc """
  Calculates total cost for a user within a date range.

  ## Parameters
    - user_id: The user ID
    - date_range: Tuple of {start_date, end_date} or nil for all time

  ## Examples

      iex> get_total_cost_by_user(user_id, {~D[2024-01-01], ~D[2024-01-31]})
      Decimal.new("12.50")

  Used by: AdminAIChatLive.Index
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

  Used by: AdminAIChatLive.Show, AIChatLive
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

  Used by: AIChatLive
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
