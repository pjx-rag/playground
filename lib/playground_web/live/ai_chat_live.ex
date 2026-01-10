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
  alias Playground.Services.OpenRouter
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

    # Fetch available AI models from OpenRouter API
    available_models = fetch_available_models()

    # Load AI default settings for admin panel
    ai_settings = load_ai_settings()

    {:ok,
     socket
     |> assign(:current_user, current_user)
     |> assign(:is_admin, is_admin)
     |> assign(:viewed_user_id, viewed_user_id)
     |> assign(:viewed_user, viewed_user)
     |> assign(:available_users, available_users)
     |> assign(:available_models, available_models)
     |> assign(:selected_model, ai_settings.default_model)
     |> assign(:ai_settings, ai_settings)
     |> assign(:chats, chats)
     |> assign(:current_chat, nil)
     |> assign(:messages, [])
     |> assign(:input_value, "")
     |> assign(:streaming_content, "")
     |> assign(:is_streaming, false)
     |> assign(:rate_limit, rate_limit)
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
                # Reload messages
                messages = AI.list_messages(current_chat.id)

                {:noreply,
                 socket
                 |> assign(:messages, messages)
                 |> assign(:input_value, "")
                 |> assign(:is_streaming, true)}

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
    current_user = socket.assigns.current_user
    viewed_user_id = socket.assigns.viewed_user_id
    # Use the default model from app settings
    default_model = socket.assigns.ai_settings.default_model
    Logger.info("Creating new chat with default model: #{default_model}")

    # Can only create chats for own account
    if viewed_user_id == current_user.id do
      case AI.create_chat(current_user, %{title: "New Chat", model: default_model}) do
        {:ok, chat} ->
          {:noreply,
           socket
           |> push_navigate(to: ~p"/chat/#{chat.id}")}

        {:error, _changeset} ->
          {:noreply, socket |> put_flash(:error, "Failed to create chat")}
      end
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
    {:noreply, push_navigate(socket, to: ~p"/chat/#{chat_id}")}
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
        |> push_navigate(to: ~p"/chat")
    end
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
      <.button
        variant="ghost"
        size="sm"
        phx-click={Fluxon.open_dialog("chat-history-sheet")}
      >
        <.icon name="hero-bars-3" class="size-5" />
        <span class="sr-only">Chat history</span>
      </.button>
    </div>
    """

    assign(socket, :header_content, header_content)
  end
end
