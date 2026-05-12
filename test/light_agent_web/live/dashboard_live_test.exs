defmodule LightAgentWeb.DashboardLiveTest do
  use LightAgentWeb.ConnCase, async: false

  alias LightAgent.Core.Worker
  import Phoenix.LiveViewTest

  setup do
    ensure_runtime_started()

    current_before = current_session_id()

    {:ok, paused_session_id} = Worker.new_session()
    {:ok, active_session_id} = Worker.new_session()

    :ok = Worker.switch_session(paused_session_id)
    {:ok, ^paused_session_id} = Worker.pause_current_session()

    :ok = Worker.switch_session(active_session_id)

    on_exit(fn ->
      _ = Worker.delete_session(paused_session_id)
      _ = Worker.delete_session(active_session_id)

      if is_binary(current_before) do
        _ = Worker.switch_session(current_before)
      end
    end)

    {:ok,
     paused_session_id: paused_session_id, active_session_id: active_session_id}
  end

  test "renders session chat form for selected session", %{
    conn: conn,
    paused_session_id: session_id
  } do
    {:ok, _view, html} = live(conn, "/dashboard?session_id=#{session_id}")

    assert html =~ "Session Chat"
    assert html =~ "id=\"session-chat-form\""
    assert html =~ "id=\"session-chat-input\""
    assert html =~ "Enter 换行，Cmd/Ctrl+Enter 发送"
    assert html =~ "session=#{session_id}"
    assert html =~ "0/4000"
    assert html =~ "Copy message"
  end

  test "submitting empty chat shows validation error", %{
    conn: conn,
    paused_session_id: session_id
  } do
    {:ok, view, _html} = live(conn, "/dashboard?session_id=#{session_id}")

    html =
      view
      |> form("#session-chat-form", chat: %{content: "   "})
      |> render_submit()

    assert html =~ "Message cannot be empty"
  end

  test "chat_input change updates char count and clears stale error", %{
    conn: conn,
    paused_session_id: session_id
  } do
    {:ok, view, _html} = live(conn, "/dashboard?session_id=#{session_id}")

    error_html =
      view
      |> form("#session-chat-form", chat: %{content: "   "})
      |> render_submit()

    assert error_html =~ "Message cannot be empty"

    changed_html =
      view
      |> form("#session-chat-form", chat: %{content: "abc"})
      |> render_change()

    refute changed_html =~ "Message cannot be empty"
    assert changed_html =~ "3/4000"
  end

  test "shortcut send triggers send flow", %{
    conn: conn,
    paused_session_id: session_id
  } do
    {:ok, view, _html} = live(conn, "/dashboard?session_id=#{session_id}")

    before_count =
      Worker.session_history(session_id)
      |> elem(1)
      |> length()

    html =
      view
      |> render_hook("chat_shortcut_send", %{
        "chat" => %{"content" => "hello from shortcut"}
      })

    assert html =~ "Message processed"

    after_count =
      Worker.session_history(session_id)
      |> elem(1)
      |> length()

    assert after_count == before_count
  end

  test "submitting chat to paused session keeps history unchanged", %{
    conn: conn,
    paused_session_id: session_id
  } do
    {:ok, view, _html} = live(conn, "/dashboard?session_id=#{session_id}")

    before_count =
      Worker.session_history(session_id)
      |> elem(1)
      |> length()

    html =
      view
      |> form("#session-chat-form", chat: %{content: "hello from dashboard"})
      |> render_submit()

    refute html =~ "Failed to send message"
    assert html =~ "Message processed"
    assert html =~ "0/4000"

    after_count =
      Worker.session_history(session_id)
      |> elem(1)
      |> length()

    assert after_count == before_count
  end

  test "select_session patches url and syncs worker current session", %{
    conn: conn,
    paused_session_id: paused_session_id,
    active_session_id: active_session_id
  } do
    {:ok, view, _html} =
      live(conn, "/dashboard?session_id=#{active_session_id}")

    assert current_session_id() == active_session_id

    view
    |> element("button[phx-value-id=\"#{paused_session_id}\"]")
    |> render_click()

    assert_patch(view, "/dashboard?session_id=#{paused_session_id}")
    assert current_session_id() == paused_session_id
  end

  test "clear_selection patches url to dashboard root", %{
    conn: conn,
    active_session_id: active_session_id
  } do
    {:ok, view, _html} =
      live(conn, "/dashboard?session_id=#{active_session_id}")

    view
    |> element("button.global-card")
    |> render_click()

    assert_patch(view, "/dashboard")
  end

  defp current_session_id do
    Worker.list_sessions()
    |> Enum.find_value(fn session ->
      if session.current, do: session.id, else: nil
    end)
  end

  defp ensure_runtime_started do
    ensure_registry_started()
    ensure_session_supervisor_started()
    ensure_pubsub_started()
    ensure_worker_started()
  end

  defp ensure_registry_started do
    case Process.whereis(LightAgent.Core.SessionRegistry) do
      nil ->
        {:ok, _pid} =
          Registry.start_link(
            keys: :unique,
            name: LightAgent.Core.SessionRegistry
          )

        :ok

      _pid ->
        :ok
    end
  end

  defp ensure_session_supervisor_started do
    case Process.whereis(LightAgent.Core.SessionSupervisor) do
      nil ->
        {:ok, _pid} = LightAgent.Core.SessionSupervisor.start_link([])
        :ok

      _pid ->
        :ok
    end
  end

  defp ensure_pubsub_started do
    case Process.whereis(LightAgent.PubSub) do
      nil ->
        {:ok, _pid} =
          Supervisor.start_link(
            [{Phoenix.PubSub, name: LightAgent.PubSub}],
            strategy: :one_for_one
          )

        :ok

      _pid ->
        :ok
    end
  end

  defp ensure_worker_started do
    case Process.whereis(LightAgent.Core.Worker) do
      nil ->
        {:ok, _pid} = Worker.start_link([])
        :ok

      _pid ->
        :ok
    end
  end
end
