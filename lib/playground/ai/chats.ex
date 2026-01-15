defmodule Playground.AI.Chats do
  @moduledoc """
  Chat management operations.

  Used by:
  - AdminAIChatLive.Index
  - AdminAIChatLive.Show
  - AIChatLive
  """

  import Ecto.Query, warn: false
  alias Playground.Repo
  alias Playground.AI.Chat
  alias Playground.Accounts.User
  alias Playground.Authorization

  @doc """
  Returns the list of chats for a user, with admin override support.

  ## Parameters
    - user_id: ID of the user whose chats to fetch
    - current_user: The user making the request (for authorization)

  ## Examples

      iex> list_for_user(user_id, current_user)
      [%Chat{}, ...]

  """
  def list_for_user(user_id, %User{} = current_user) do
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

  Used by: AdminAIChatLive.Index
  """
  def list_all(%User{} = current_user) do
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

  Used by: AIChatLive
  """
  def get!(id, user_id) do
    from(c in Chat,
      where: c.id == ^id and c.user_id == ^user_id,
      preload: [:user]
    )
    |> Repo.one!()
  end

  @doc """
  Gets a single chat for admin viewing (no user_id check).

  Used by: AdminAIChatLive.Show
  """
  def get_for_admin!(id, %User{} = admin) do
    if Authorization.can?(admin, "ai_chat:view_all") do
      Repo.get!(Chat, id) |> Repo.preload(:user)
    else
      raise Ecto.NoResultsError, queryable: Chat
    end
  end

  @doc """
  Creates a chat for a user.

  Returns `{:ok, chat}` on success or `{:error, changeset}` on failure.
  """
  def create(%User{} = user, attrs \\ %{}) do
    # Generate unique title based on existing chats
    default_title = generate_default_title(user.id)

    %Chat{}
    |> Chat.changeset(Map.merge(%{user_id: user.id, title: default_title}, attrs))
    |> Repo.insert()
  end

  @doc """
  Updates a chat.

  ## Examples

      iex> update(chat, %{title: "New Title"})
      {:ok, %Chat{}}

      iex> update(chat, %{title: nil})
      {:error, %Ecto.Changeset{}}

  """
  def update(%Chat{} = chat, attrs) do
    chat
    |> Chat.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Chat with authorization check.
  """
  def delete(%Chat{} = chat, %User{} = user) do
    if chat.user_id == user.id or Authorization.can?(user, "ai_chat:delete_any") do
      Repo.delete(chat)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Deletes all chats for a user.

  Returns `{:ok, count}` where count is the number of deleted chats.
  """
  def delete_all(%User{} = user) do
    query = from(c in Chat, where: c.user_id == ^user.id)

    case Repo.delete_all(query) do
      {count, _} -> {:ok, count}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking chat changes.
  """
  def change(%Chat{} = chat, attrs \\ %{}) do
    Chat.changeset(chat, attrs)
  end

  @doc """
  Auto-generates a chat title from the first user message (truncated to 50 chars).
  """
  def auto_generate_title(%Chat{} = chat) do
    # Delegate query to Messages context
    first_message = Playground.AI.Messages.get_first_user_message(chat.id)

    if first_message do
      title =
        first_message.content
        |> String.slice(0, 50)
        |> String.trim()
        |> then(fn s -> if String.length(first_message.content) > 50, do: s <> "...", else: s end)

      __MODULE__.update(chat, %{title: title})
    else
      {:ok, chat}
    end
  end

  @doc """
  Clears the processing flag on a chat (e.g., after AI response completes).
  """
  def clear_processing_flag(%Chat{} = chat) do
    __MODULE__.update(chat, %{processing: false})
  end

  # Private functions

  defp generate_default_title(user_id) do
    count =
      from(c in Chat, where: c.user_id == ^user_id, select: count(c.id))
      |> Repo.one()

    "Chat #{count + 1}"
  end
end
