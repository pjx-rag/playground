defmodule Playground.AI do
  @moduledoc """
  The AI context facade.

  Delegates to domain-specific mini-contexts:
  - `AI.Chats` - Chat operations (create, update, delete, list)
  - `AI.Messages` - Message operations (create user/assistant messages)
  - `AI.RateLimiting` - Rate limit checking and tracking
  - `AI.Analytics` - Cost tracking and statistics

  This facade provides a clean public API while keeping implementation
  details organized into focused, manageable modules.
  """

  alias Playground.AI.{Chats, Messages, RateLimiting, Analytics}

  # ============================================================================
  # Chat Functions - Delegate to AI.Chats
  # ============================================================================

  @doc "See `AI.Chats.list_for_user/2`"
  defdelegate list_user_chats(user_id, current_user), to: Chats, as: :list_for_user

  @doc "See `AI.Chats.list_all/1`"
  defdelegate list_all_chats(current_user), to: Chats, as: :list_all

  @doc "See `AI.Chats.get!/2`"
  defdelegate get_chat!(id, user_id), to: Chats, as: :get!

  @doc "See `AI.Chats.get_for_admin!/2`"
  defdelegate get_chat_for_admin!(id, admin), to: Chats, as: :get_for_admin!

  @doc "See `AI.Chats.create/2`"
  defdelegate create_chat(user, attrs \\ %{}), to: Chats, as: :create

  @doc "See `AI.Chats.update/2`"
  defdelegate update_chat(chat, attrs), to: Chats, as: :update

  @doc "See `AI.Chats.delete/2`"
  defdelegate delete_chat(chat, user), to: Chats, as: :delete

  @doc "See `AI.Chats.delete_all/1`"
  defdelegate delete_all_user_chats(user), to: Chats, as: :delete_all

  @doc "See `AI.Chats.change/2`"
  defdelegate change_chat(chat, attrs \\ %{}), to: Chats, as: :change

  @doc "See `AI.Chats.auto_generate_title/1`"
  defdelegate auto_generate_chat_title(chat), to: Chats, as: :auto_generate_title

  @doc "See `AI.Chats.clear_processing_flag/1`"
  defdelegate clear_processing_flag(chat), to: Chats, as: :clear_processing_flag

  # ============================================================================
  # Message Functions - Delegate to AI.Messages
  # ============================================================================

  @doc "See `AI.Messages.list_for_chat/2`"
  defdelegate list_messages(chat_id, opts \\ []), to: Messages, as: :list_for_chat

  @doc "See `AI.Messages.create_user_message/2`"
  defdelegate create_user_message(chat, content), to: Messages

  @doc "See `AI.Messages.create_assistant_message/5`"
  defdelegate create_assistant_message(chat, content, tokens_used, cost_usd, api_request_log_id),
    to: Messages

  @doc "See `AI.Messages.create_assistant_message/6`"
  defdelegate create_assistant_message(chat, content, tokens_used, cost_usd, api_request_log_id, rag_attrs),
    to: Messages

  # ============================================================================
  # Rate Limiting - Delegate to AI.RateLimiting
  # ============================================================================

  @doc "See `AI.RateLimiting.check_rate_limit/1`"
  defdelegate check_rate_limit(user_id), to: RateLimiting

  @doc "See `AI.RateLimiting.record_request/1`"
  defdelegate record_request(user_id), to: RateLimiting

  @doc "See `AI.RateLimiting.cleanup_old_tracking/0`"
  defdelegate cleanup_old_request_tracking(), to: RateLimiting, as: :cleanup_old_tracking

  @doc "See `AI.RateLimiting.get_usage_stats/1`"
  defdelegate get_usage_stats(user_id), to: RateLimiting

  # ============================================================================
  # Analytics - Delegate to AI.Analytics
  # ============================================================================

  @doc "See `AI.Analytics.get_total_cost_by_user/2`"
  defdelegate get_total_cost_by_user(user_id, date_range \\ nil), to: Analytics

  @doc "See `AI.Analytics.get_total_cost_by_chat/1`"
  defdelegate get_total_cost_by_chat(chat_id), to: Analytics

  @doc "See `AI.Analytics.get_chat_stats/1`"
  defdelegate get_chat_stats(chat_id), to: Analytics
end
