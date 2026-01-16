defmodule PlaygroundWeb.AIChatLive do
  @moduledoc """
  LiveView for AI chat interface with streaming support.

  Features:
  - Real-time token streaming via PubSub
  - Chat history management
  - Rate limiting display
  - Admin user selector for viewing other users' chats
  - Markdown rendering with MDEx
  """

  use PlaygroundWeb, :live_view

  alias Playground.AI
  alias Playground.Accounts
  alias Playground.Authorization
  alias Playground.Services.AI.OpenRouter
  alias Playground.Settings

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    # Check if user is admin
    is_admin = Authorization.can?(current_user, "ai_chat:view_all")

    # Default to viewing own chats
    viewed_user_id = current_user.id
    viewed_user = current_user

    # Load available users for admin dropdown
    available_users =
      if is_admin do
        Accounts.list_users()
      else
        []
      end

    # Load chats for viewed user
    chats = AI.list_user_chats(viewed_user_id, current_user)

    # Get rate limit stats
    rate_limit = AI.get_usage_stats(viewed_user_id)

    # Load AI default settings for admin panel
    ai_settings = load_ai_settings()

    # Start with default model, fetch full list async to avoid blocking mount
    default_models = [{"⭐ Mistral Devstral 2 (Recommended)", "mistralai/devstral-2512:free"}]

    # Trigger async model loading only on connected mount
    if connected?(socket), do: send(self(), :load_available_models)

    {:ok,
     socket
     |> assign(:current_user, current_user)
     |> assign(:is_admin, is_admin)
     |> assign(:viewed_user_id, viewed_user_id)
     |> assign(:viewed_user, viewed_user)
     |> assign(:available_users, available_users)
     |> assign(:available_models, default_models)
     |> assign(:models_loading, true)
     |> assign(:selected_model, ai_settings.default_model)
     |> assign(:ai_settings, ai_settings)
     |> assign(:chats, chats)
     |> assign(:current_chat, nil)
     |> assign(:messages, [])
     |> assign(:input_value, "")
     |> assign(:streaming_content, "")
     |> assign(:is_streaming, false)
     |> assign(:rate_limit, rate_limit)
     |> assign(:viewing_chunk, nil)
     |> assign(:page_title, "AI Chat")
     |> assign(:hide_header_padding, true)
     |> assign_header_content()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    current_user = socket.assigns.current_user
    is_admin = socket.assigns.is_admin

    # Unsubscribe from previous chat to prevent memory leak
    case Map.get(socket.assigns, :current_chat) do
      nil ->
        :ok

      current_chat ->
        Phoenix.PubSub.unsubscribe(
          Playground.PubSub,
          "ai_chat:#{current_chat.user_id}:#{current_chat.id}"
        )
    end

    # Handle user_id parameter for admin
    {viewed_user_id, viewed_user} =
      case params do
        %{"user_id" => "all"} when is_admin ->
          {nil, nil}

        %{"user_id" => user_id} when is_admin ->
          user = Accounts.get_user!(user_id)
          {user.id, user}

        _ ->
          {current_user.id, current_user}
      end

    # Reload chats for new viewed user
    chats =
      if viewed_user_id do
        AI.list_user_chats(viewed_user_id, current_user)
      else
        AI.list_all_chats(current_user)
      end

    # Handle chat_id parameter
    socket =
      case params do
        %{"id" => chat_id} ->
          load_chat(socket, chat_id, viewed_user_id)

        _ ->
          socket
      end

    {:noreply,
     socket
     |> assign(:viewed_user_id, viewed_user_id)
     |> assign(:viewed_user, viewed_user)
     |> assign(:chats, chats)
     |> assign_header_content()}
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    current_user = socket.assigns.current_user
    viewed_user_id = socket.assigns.viewed_user_id
    current_chat = socket.assigns.current_chat

    cond do
      # Can only send messages when viewing own chats
      viewed_user_id != current_user.id ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot send messages while viewing another user's chats")}

      # Must have a current chat
      is_nil(current_chat) ->
        {:noreply, socket |> put_flash(:error, "Please select or create a chat first")}

      # Check rate limit
      true ->
        case AI.check_rate_limit(current_user.id) do
          {:ok, _remaining} ->
            case AI.create_user_message(current_chat, content) do
              {:ok, _message} ->
                # Auto-rename chat on first message if title is still "New Chat"
                {updated_chat, chats} =
                  if current_chat.title == "New Chat" and socket.assigns.messages == [] do
                    title = generate_chat_title(content)

                    case AI.update_chat(current_chat, %{title: title}) do
                      {:ok, chat} ->
                        # Reload chats list to reflect the new title
                        {chat, AI.list_user_chats(current_user.id, current_user)}

                      {:error, _} ->
                        {current_chat, socket.assigns.chats}
                    end
                  else
                    {current_chat, socket.assigns.chats}
                  end

                # Reload messages
                messages = AI.list_messages(current_chat.id)

                {:noreply,
                 socket
                 |> assign(:current_chat, updated_chat)
                 |> assign(:chats, chats)
                 |> assign(:messages, messages)
                 |> assign(:input_value, "")
                 |> assign(:is_streaming, true)
                 |> assign_header_content()}

              {:error, :chat_is_processing} ->
                {:noreply,
                 socket
                 |> put_flash(:error, "Please wait for the current response to complete")}

              {:error, changeset} ->
                {:noreply,
                 socket
                 |> put_flash(:error, "Failed to send message: #{inspect(changeset)}")}
            end

          {:error, {:rate_limit_exceeded, window}} ->
            window_name =
              case window do
                :per_minute -> "minute"
                :per_hour -> "hour"
                :per_day -> "day"
              end

            {:noreply,
             socket
             |> put_flash(:error, "Rate limit exceeded: too many requests per #{window_name}")}
        end
    end
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    viewed_user_id = socket.assigns.viewed_user_id
    current_user = socket.assigns.current_user

    # Can only create chats for own account
    if viewed_user_id == current_user.id do
      send(self(), :create_new_chat)
      {:noreply, socket}
    else
      {:noreply, socket |> put_flash(:error, "Cannot create chats for other users")}
    end
  end

  @impl true
  def handle_event("update_ai_settings", params, socket) do
    # Admin only - update app settings
    if socket.assigns.is_admin do
      Logger.debug("Updating AI settings: #{inspect(params)}")

      # Update each setting that was provided
      if model = params["default_model"] do
        available_model_ids = Enum.map(socket.assigns.available_models, fn {_label, id} -> id end)

        if model in available_model_ids do
          Settings.set_app_setting("ai_default_model", model)
        end
      end

      if rag_mode = params["rag_mode"] do
        if rag_mode in ["rag", "agentic_rag"] do
          Settings.set_app_setting("rag_mode", rag_mode)
        end
      end

      case params["temperature"] do
        value when value not in [nil, ""] -> Settings.set_app_setting("ai_temperature", value)
        _ -> :ok
      end

      case params["max_tokens"] do
        value when value not in [nil, ""] -> Settings.set_app_setting("ai_max_tokens", value)
        _ -> :ok
      end

      case params["top_p"] do
        value when value not in [nil, ""] -> Settings.set_app_setting("ai_top_p", value)
        _ -> :ok
      end

      case params["frequency_penalty"] do
        value when value not in [nil, ""] -> Settings.set_app_setting("ai_frequency_penalty", value)
        _ -> :ok
      end

      case params["presence_penalty"] do
        value when value not in [nil, ""] -> Settings.set_app_setting("ai_presence_penalty", value)
        _ -> :ok
      end

      # Reload settings
      ai_settings = load_ai_settings()

      {:noreply,
       socket
       |> assign(:ai_settings, ai_settings)
       |> assign(:selected_model, ai_settings.default_model)}
    else
      {:noreply, socket |> put_flash(:error, "Only admins can change AI settings")}
    end
  end

  @impl true
  def handle_event("rename_chat", %{"title" => new_title}, socket) do
    current_chat = socket.assigns.current_chat
    current_user = socket.assigns.current_user

    # Only rename if title actually changed and is not empty
    new_title = String.trim(new_title)

    if new_title != "" and new_title != current_chat.title do
      case AI.update_chat(current_chat, %{title: new_title}) do
        {:ok, updated_chat} ->
          # Reload chats list to reflect the new title
          chats = AI.list_user_chats(current_user.id, current_user)

          {:noreply,
           socket
           |> assign(:current_chat, updated_chat)
           |> assign(:chats, chats)
           |> assign_header_content()}

        {:error, _changeset} ->
          {:noreply, socket |> put_flash(:error, "Failed to rename chat")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_chat", %{"chat_id" => chat_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat/#{chat_id}")}
  end

  @impl true
  def handle_event("delete_chat", %{"chat_id" => chat_id}, socket) do
    current_user = socket.assigns.current_user
    current_chat = socket.assigns.current_chat
    chat = AI.get_chat!(chat_id, current_user.id)

    case AI.delete_chat(chat, current_user) do
      {:ok, _} ->
        chats = AI.list_user_chats(current_user.id, current_user)

        # Clear current chat if we deleted the one being viewed
        socket =
          if current_chat && current_chat.id == chat.id do
            socket
            |> assign(:current_chat, nil)
            |> assign(:messages, [])
          else
            socket
          end

        {:noreply, assign(socket, :chats, chats)}

      {:error, :unauthorized} ->
        {:noreply, socket |> put_flash(:error, "Unauthorized to delete this chat")}
    end
  end

  @impl true
  def handle_event("delete_all_chats", _params, socket) do
    current_user = socket.assigns.current_user
    viewed_user_id = socket.assigns.viewed_user_id

    # Only allow deleting own chats
    if viewed_user_id == current_user.id do
      case AI.delete_all_user_chats(current_user) do
        {:ok, count} ->
          Logger.info("Deleted #{count} chats for user #{current_user.id}")

          {:noreply,
           socket
           |> assign(:chats, [])
           |> assign(:current_chat, nil)
           |> assign(:messages, [])
           |> put_flash(:info, "Deleted #{count} chats")}

        {:error, reason} ->
          {:noreply, socket |> put_flash(:error, "Failed to delete chats: #{inspect(reason)}")}
      end
    else
      {:noreply, socket |> put_flash(:error, "Cannot delete chats for other users")}
    end
  end

  @impl true
  def handle_event("change_viewed_user", %{"user_id" => user_id}, socket) do
    path =
      case user_id do
        "all" -> ~p"/chat?user_id=all"
        "" -> ~p"/chat"
        id -> ~p"/chat?user_id=#{id}"
      end

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("view_chunk", %{"chunk_id" => chunk_id}, socket) do
    case Playground.Repo.get(Playground.RAG.Chunk, chunk_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Chunk not found")}

      chunk ->
        {:noreply, assign(socket, :viewing_chunk, chunk)}
    end
  end

  @impl true
  def handle_info(:streaming_start, socket) do
    {:noreply,
     socket
     |> assign(:is_streaming, true)
     |> assign(:streaming_content, "")}
  end

  @impl true
  def handle_info({:token_chunk, chunk}, socket) do
    updated_content = socket.assigns.streaming_content <> chunk

    {:noreply, assign(socket, :streaming_content, updated_content)}
  end

  @impl true
  def handle_info({:message_completed, _message}, socket) do
    current_chat = socket.assigns.current_chat

    # Reload messages to include the completed assistant message
    messages = AI.list_messages(current_chat.id)

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:is_streaming, false)
     |> assign(:streaming_content, "")}
  end

  @impl true
  def handle_info({:message_failed, _reason}, socket) do
    current_chat = socket.assigns.current_chat

    # Reload messages in case an error message was saved
    messages = AI.list_messages(current_chat.id)

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:is_streaming, false)
     |> assign(:streaming_content, "")
     |> put_flash(:error, "AI chat service is temporarily unavailable. Please try again.")}
  end

  @impl true
  def handle_info({:error, _message}, socket) do
    current_chat = socket.assigns.current_chat

    # Reload messages in case an error message was saved
    messages = AI.list_messages(current_chat.id)

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:is_streaming, false)
     |> assign(:streaming_content, "")
     |> put_flash(:error, "AI chat service is temporarily unavailable. Please try again.")}
  end

  @impl true
  def handle_info(:load_available_models, socket) do
    # Fetch models async to avoid blocking mount
    available_models = fetch_available_models()

    {:noreply,
     socket
     |> assign(:available_models, available_models)
     |> assign(:models_loading, false)}
  end

  @impl true
  def handle_info(:create_new_chat, socket) do
    current_user = socket.assigns.current_user
    default_model = socket.assigns.ai_settings.default_model
    Logger.info("Creating new chat with default model: #{default_model}")

    case AI.create_chat(current_user, %{title: "New Chat", model: default_model}) do
      {:ok, chat} ->
        # Use push_patch to avoid full page reload and browser loading indicator
        {:noreply, push_patch(socket, to: ~p"/chat/#{chat.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create chat")}
    end
  end

  defp load_chat(socket, chat_id, viewed_user_id) do
    current_user = socket.assigns.current_user

    try do
      chat =
        if viewed_user_id do
          AI.get_chat!(chat_id, viewed_user_id)
        else
          AI.get_chat_for_admin!(chat_id, current_user)
        end

      messages = AI.list_messages(chat_id)

      # Subscribe to PubSub for streaming
      Phoenix.PubSub.subscribe(Playground.PubSub, "ai_chat:#{chat.user_id}:#{chat_id}")

      socket
      |> assign(:current_chat, chat)
      |> assign(:messages, messages)
      |> assign(:is_streaming, chat.is_processing)
    rescue
      Ecto.NoResultsError ->
        socket
        |> put_flash(:error, "Chat not found or unauthorized")
        |> push_patch(to: ~p"/chat")
    end
  end

  # Generate a chat title from the first message content
  # Takes the first ~50 chars, ending at a word boundary
  defp generate_chat_title(content) do
    content
    |> String.trim()
    |> String.slice(0, 60)
    |> then(fn text ->
      if String.length(content) > 60 do
        # Find last space to avoid cutting words
        case String.last(text) do
          " " ->
            String.trim_trailing(text) <> "..."

          _ ->
            case :binary.match(text, " ") do
              :nomatch ->
                text <> "..."

              _ ->
                # Trim to last complete word
                text
                |> String.split(" ")
                |> Enum.drop(-1)
                |> Enum.join(" ")
                |> Kernel.<>("...")
            end
        end
      else
        text
      end
    end)
  end

  defp fetch_available_models do
    case OpenRouter.list_models() do
      {:ok, %{body: %{"data" => models}}} ->
        models
        |> Enum.sort_by(& &1["name"])
        |> Enum.map(fn model ->
          id = model["id"]
          name = model["name"] || id
          # Add free indicator if pricing is $0
          pricing = model["pricing"] || %{}
          prompt_price = pricing["prompt"] || "0"
          is_free = prompt_price == "0"

          # Mark Mistral as recommended since we know it works
          label = cond do
            id == "mistralai/devstral-2512:free" -> "⭐ #{name} (Recommended)"
            is_free -> "🆓 #{name}"
            true -> name
          end

          {label, id}
        end)

      {:error, reason} ->
        Logger.warning("Failed to fetch models from OpenRouter: #{inspect(reason)}")
        # Return only the known working model if API fails
        [
          {"⭐ Mistral Devstral 2 (Recommended)", "mistralai/devstral-2512:free"}
        ]
    end
  end

  defp load_ai_settings do
    %{
      default_model: Settings.get_app_setting_value("ai_default_model", "mistralai/devstral-2512:free"),
      rag_mode: Settings.get_app_setting_value("rag_mode", "agentic_rag"),
      temperature: Settings.get_app_setting_value("ai_temperature", "0.7"),
      max_tokens: Settings.get_app_setting_value("ai_max_tokens", "4096"),
      top_p: Settings.get_app_setting_value("ai_top_p", "1.0"),
      frequency_penalty: Settings.get_app_setting_value("ai_frequency_penalty", "0.0"),
      presence_penalty: Settings.get_app_setting_value("ai_presence_penalty", "0.0")
    }
  end

  defp assign_header_content(socket) do
    assigns = socket.assigns

    header_content = ~H"""
    <div class="flex items-center justify-between">
      <div class="flex-1 min-w-0 mr-4">
        <%= if @current_chat do %>
          <%= if @viewed_user_id == @current_user.id do %>
            <.form for={%{}} phx-change="rename_chat" phx-submit="rename_chat" class="contents">
              <input
                type="text"
                name="title"
                value={@current_chat.title}
                phx-debounce="300"
                class="text-sm font-medium text-foreground bg-transparent border-0 border-b border-transparent hover:border-base focus:border-primary focus:ring-0 w-full max-w-md px-0 py-0 transition-colors"
              />
            </.form>
          <% else %>
            <span class="text-sm font-medium text-foreground">{@current_chat.title}</span>
          <% end %>
          <span class="text-xs text-muted-foreground ml-2">({@current_chat.model})</span>
        <% else %>
          <span class="text-sm text-muted-foreground">Select or create a chat</span>
        <% end %>
      </div>
      <div class="flex items-center gap-1">
        <%= if @viewed_user_id == @current_user.id do %>
          <.button
            variant="ghost"
            size="sm"
            phx-click="new_chat"
          >
            <.icon name="hero-plus" class="size-5" />
            <span class="sr-only">New chat</span>
          </.button>
        <% end %>
        <%= if @is_admin do %>
          <.button
            variant="ghost"
            size="sm"
            phx-click={Fluxon.open_dialog("ai-settings-sheet")}
          >
            <.icon name="hero-cog-6-tooth" class="size-5" />
            <span class="sr-only">AI Settings</span>
          </.button>
        <% end %>
        <.button
          variant="ghost"
          size="sm"
          phx-click={Fluxon.open_dialog("chat-history-sheet")}
        >
          <.icon name="hero-bars-3" class="size-5" />
          <span class="sr-only">Chat history</span>
        </.button>
      </div>
    </div>
    """

    assign(socket, :header_content, header_content)
  end

  @doc """
  Extracts citation numbers referenced in the message content.
  Parses patterns like [1], [2], [10] from the text.
  """
  def extract_used_citations(content) when is_binary(content) do
    ~r/\[(\d+)\]/
    |> Regex.scan(content)
    |> Enum.map(fn [_, num] -> String.to_integer(num) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def extract_used_citations(_), do: []

  @doc """
  Filters citations to only those actually referenced in the message.
  """
  def filter_used_citations(citations, content) when is_list(citations) do
    used_positions = extract_used_citations(content)

    citations
    |> Enum.filter(fn citation ->
      position = citation["position"]
      position in used_positions
    end)
  end

  def filter_used_citations(_, _), do: []
end
