defmodule LightAgentWeb.DashboardLive do
  use LightAgentWeb, :live_view

  alias LightAgent.Dashboard
  alias LightAgent.Dashboard.Events

  @poll_interval_ms 5_000

  @impl true
  def mount(params, _session, socket) do
    selected_session_id = params["session_id"]

    if connected?(socket) do
      :ok = Events.subscribe_sessions()
      :ok = Events.subscribe_global_context()
      subscribe_selected_session(selected_session_id)
      schedule_poll()
    end

    socket =
      socket
      |> assign(:selected_session_id, selected_session_id)
      |> assign(:error, nil)
      |> assign(:chat_input, "")
      |> assign(:chat_error, nil)
      |> assign(:chat_notice, nil)
      |> assign(:chat_submitting, false)
      |> assign(:last_updated_at, DateTime.utc_now())
      |> load_dashboard_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_session_id = params["session_id"]

    socket =
      socket
      |> maybe_resubscribe_session(selected_session_id)
      |> sync_system_session(selected_session_id)
      |> assign(:selected_session_id, selected_session_id)
      |> assign(:chat_error, nil)
      |> assign(:chat_notice, nil)
      |> load_session_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_session", %{"id" => session_id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/dashboard?session_id=#{session_id}"
     )}
  end

  @impl true
  def handle_event("chat_input", %{"chat" => %{"content" => content}}, socket) do
    {:noreply,
     socket
     |> assign(:chat_input, content)
     |> assign(:chat_error, nil)
     |> assign(:chat_notice, nil)}
  end

  @impl true
  def handle_event(
        "chat_shortcut_send",
        %{"chat" => %{"content" => content}},
        socket
      ) do
    {:noreply, submit_chat(socket, content)}
  end

  @impl true
  def handle_event("send_chat", %{"chat" => %{"content" => content}}, socket) do
    {:noreply, submit_chat(socket, content)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, refresh_dashboard(socket)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard")}
  end

  @impl true
  def handle_info({:dashboard_event, _topic, _payload}, socket) do
    {:noreply, refresh_dashboard(socket)}
  end

  @impl true
  def handle_info(:poll, socket) do
    if connected?(socket), do: schedule_poll()
    {:noreply, refresh_dashboard(socket)}
  end

  defp submit_chat(socket, content) do
    selected_session_id = socket.assigns.selected_session_id

    socket =
      socket
      |> assign(:chat_submitting, true)
      |> assign(:chat_error, nil)
      |> assign(:chat_notice, nil)
      |> assign(:chat_input, content)

    cond do
      is_nil(selected_session_id) ->
        socket
        |> assign(:chat_submitting, false)
        |> assign(:chat_error, "Select a session before sending a message")

      String.trim(content) == "" ->
        socket
        |> assign(:chat_submitting, false)
        |> assign(:chat_error, "Message cannot be empty")

      true ->
        case Dashboard.send_session_message(selected_session_id, content) do
          {:ok, {:done, _reply, _step_usage}} ->
            socket
            |> assign(:chat_submitting, false)
            |> assign(:chat_input, "")
            |> assign(:chat_error, nil)
            |> assign(:chat_notice, "Message processed")
            |> refresh_dashboard()
            |> push_event("chat_clear_input", %{})

          {:error, :session_not_found} ->
            socket
            |> assign(:chat_submitting, false)
            |> assign(:chat_error, "Session not found or has been deleted")
            |> load_session_data()

          {:error, :empty_message} ->
            socket
            |> assign(:chat_submitting, false)
            |> assign(:chat_error, "Message cannot be empty")

          {:error, reason} ->
            socket
            |> assign(:chat_submitting, false)
            |> assign(
              :chat_error,
              "Failed to send message: #{inspect(reason)}"
            )

          _ ->
            socket
            |> assign(:chat_submitting, false)
            |> assign(:chat_error, "Failed to send message")
        end
    end
  end

  defp refresh_dashboard(socket) do
    socket
    |> load_dashboard_data()
    |> assign(:last_updated_at, DateTime.utc_now())
  end

  defp load_dashboard_data(socket) do
    socket
    |> assign(:sessions, Dashboard.list_sessions())
    |> assign(:global_context, Dashboard.get_effective_global_context())
    |> load_session_data()
  end

  defp load_session_data(socket) do
    selected_session_id = socket.assigns.selected_session_id

    case selected_session_id do
      nil ->
        socket
        |> assign(:session_detail, nil)
        |> assign(:session_history, [])
        |> assign(:error, nil)

      session_id ->
        with {:ok, detail} <- Dashboard.get_session_detail(session_id),
             {:ok, history} <- Dashboard.get_session_history(session_id) do
          socket
          |> assign(:session_detail, detail)
          |> assign(:session_history, Enum.reverse(history))
          |> assign(:error, nil)
        else
          {:error, :session_not_found} ->
            socket
            |> assign(:session_detail, nil)
            |> assign(:session_history, [])
            |> assign(:error, "Session not found or has been deleted")

          {:error, reason} ->
            socket
            |> assign(:session_detail, nil)
            |> assign(:session_history, [])
            |> assign(:error, "Failed to load session data: #{inspect(reason)}")
        end
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp subscribe_selected_session(nil), do: :ok

  defp subscribe_selected_session(session_id) when is_binary(session_id) do
    Events.subscribe_session(session_id)
  end

  defp maybe_resubscribe_session(socket, selected_session_id) do
    previous = socket.assigns[:selected_session_id]

    cond do
      previous == selected_session_id ->
        socket

      is_binary(previous) and previous != "" ->
        Events.unsubscribe_session(previous)
        subscribe_selected_session(selected_session_id)
        socket

      true ->
        subscribe_selected_session(selected_session_id)
        socket
    end
  end

  defp sync_system_session(socket, nil), do: socket

  defp sync_system_session(socket, session_id) when is_binary(session_id) do
    case Dashboard.switch_session(session_id) do
      :ok ->
        socket

      {:error, :session_not_found} ->
        assign(socket, :error, "Session not found or has been deleted")

      {:error, reason} ->
        assign(socket, :error, "Failed to switch session: #{inspect(reason)}")
    end
  end
end
