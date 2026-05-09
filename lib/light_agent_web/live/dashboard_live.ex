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
      |> assign(:selected_session_id, selected_session_id)
      |> load_session_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_session", %{"id" => session_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard?session_id=#{session_id}")}
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
            |> assign(:error, "session 不存在或已被删除")

          {:error, reason} ->
            socket
            |> assign(:session_detail, nil)
            |> assign(:session_history, [])
            |> assign(:error, "加载 session 数据失败: #{inspect(reason)}")
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
end
