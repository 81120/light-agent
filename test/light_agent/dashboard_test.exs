defmodule LightAgent.DashboardTest do
  use ExUnit.Case, async: false

  alias LightAgent.Core.Worker
  alias LightAgent.Dashboard

  setup do
    ensure_runtime_started()

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "light_agent_dashboard_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    original_root = Application.get_env(:light_agent, :agent_external_root)
    Application.put_env(:light_agent, :agent_external_root, tmp_dir)

    original_current = current_session_id()

    {:ok, paused_session_id} = Worker.new_session()
    {:ok, active_session_id} = Worker.new_session()

    :ok = Worker.switch_session(paused_session_id)
    {:ok, ^paused_session_id} = Worker.pause_current_session()
    :ok = Worker.switch_session(active_session_id)

    on_exit(fn ->
      _ = Worker.delete_session(paused_session_id)
      _ = Worker.delete_session(active_session_id)

      if is_binary(original_current) do
        _ = Worker.switch_session(original_current)
      end

      if original_root do
        Application.put_env(:light_agent, :agent_external_root, original_root)
      else
        Application.delete_env(:light_agent, :agent_external_root)
      end

      File.rm_rf!(tmp_dir)
    end)

    {:ok,
     paused_session_id: paused_session_id, active_session_id: active_session_id}
  end

  test "run_agent_step_for_session targets selected session without switching current",
       ctx do
    assert {:done, message, _step_usage} =
             Worker.run_agent_step_for_session(ctx.paused_session_id, "hello")

    assert message ==
             "Current session is paused. Run /resume before continuing."

    assert current_session_id() == ctx.active_session_id
  end

  test "run_agent_step_for_session returns session-missing message for unknown id" do
    assert {:done, message, _step_usage} =
             Worker.run_agent_step_for_session(
               "missing-session-id",
               "hello"
             )

    assert message ==
             "Session does not exist. Select an available session and try again."
  end

  test "send_session_message validates empty content", ctx do
    assert {:error, :empty_message} =
             Dashboard.send_session_message(ctx.active_session_id, "   ")
  end

  test "send_session_message validates input types" do
    assert {:error, :invalid_input} = Dashboard.send_session_message(:bad, 1)
  end

  test "send_session_message returns session not found for unknown id" do
    assert {:error, :session_not_found} =
             Dashboard.send_session_message("missing-session-id", "hello")
  end

  test "send_session_message reuses session run flow", ctx do
    assert {:ok, {:done, message, _step_usage}} =
             Dashboard.send_session_message(ctx.paused_session_id, "hello")

    assert message ==
             "Current session is paused. Run /resume before continuing."
  end

  test "switch_session updates worker current session", ctx do
    assert :ok = Dashboard.switch_session(ctx.paused_session_id)
    assert current_session_id() == ctx.paused_session_id
  end

  test "switch_session validates input" do
    assert {:error, :invalid_session_id} = Dashboard.switch_session(:bad)
  end

  test "switch_session returns not found for unknown id" do
    assert {:error, :session_not_found} =
             Dashboard.switch_session("missing-session-id")
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
