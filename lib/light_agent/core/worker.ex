defmodule LightAgent.Core.Worker do
  use GenServer
  require Logger

  alias LightAgent.Core.SessionMemoryStore
  alias LightAgent.Core.SessionServer
  alias LightAgent.Core.SessionSupervisor
  alias LightAgent.Core.Worker.Session
  alias LightAgent.Core.Worker.Usage

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def run_agent(user_input \\ nil) do
    case run_agent_step(user_input) do
      {:running, _tool_results, _step_usage} ->
        run_agent()

      {:done, content, _step_usage} ->
        Logger.debug("Agent 完成任务：#{content}")
        content
    end
  end

  def run_agent_step(user_input \\ nil) do
    GenServer.call(__MODULE__, {:run_agent_step, user_input}, 300_000)
  end

  def current_token_usage() do
    GenServer.call(__MODULE__, :current_token_usage)
  end

  def new_session() do
    GenServer.call(__MODULE__, :new_session)
  end

  def list_sessions() do
    GenServer.call(__MODULE__, :list_sessions)
  end

  def pause_current_session() do
    GenServer.call(__MODULE__, :pause_current_session)
  end

  def switch_session(session_id) do
    GenServer.call(__MODULE__, {:switch_session, session_id})
  end

  def resume_session(session_id) do
    GenServer.call(__MODULE__, {:resume_session, session_id})
  end

  def delete_session(session_id) do
    GenServer.call(__MODULE__, {:delete_session, session_id})
  end

  def current_history() do
    GenServer.call(__MODULE__, :current_history)
  end

  def current_mode() do
    GenServer.call(__MODULE__, :current_mode)
  end

  def set_mode(mode) when mode in [:normal, :plan] do
    GenServer.call(__MODULE__, {:set_mode, mode})
  end

  def current_plan() do
    GenServer.call(__MODULE__, :current_plan)
  end

  def apply_plan() do
    GenServer.call(__MODULE__, :apply_plan)
  end

  def reset_plan() do
    GenServer.call(__MODULE__, :reset_plan)
  end

  def update_plan(plan) when is_map(plan) do
    GenServer.call(__MODULE__, {:update_plan, plan})
  end

  def plan_progress() do
    GenServer.call(__MODULE__, :plan_progress)
  end

  @impl true
  def init(_opts) do
    case restore_or_boot_sessions() do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:new_session, _from, state) do
    session_id = new_session_id()

    case start_session_server(session_id) do
      :ok ->
        state =
          state
          |> put_in([:sessions, session_id], %{status: :active})
          |> Map.put(:current_session_id, session_id)

        {:reply, {:ok, session_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions =
      state.sessions
      |> Enum.map(fn {id, session} ->
        %{
          id: id,
          status: session.status,
          current: id == state.current_session_id
        }
      end)
      |> Enum.sort_by(&Session.session_sort_key/1)

    {:reply, sessions, state}
  end

  @impl true
  def handle_call(:pause_current_session, _from, state) do
    session_id = state.current_session_id

    case call_session(session_id, :pause) do
      {:ok, :ok} ->
        state =
          put_in(state, [:sessions, session_id, :status], :paused)

        {:reply, {:ok, session_id}, state}

      {:error, :session_not_found} ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call({:switch_session, session_id}, _from, state) do
    if Map.has_key?(state.sessions, session_id) and
         session_alive?(session_id) do
      {:reply, :ok, %{state | current_session_id: session_id}}
    else
      {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call({:resume_session, session_id}, _from, state) do
    if Map.has_key?(state.sessions, session_id) do
      case call_session(session_id, :resume) do
        {:ok, :ok} ->
          state =
            put_in(state, [:sessions, session_id, :status], :active)

          {:reply, :ok, state}

        {:error, :session_not_found} ->
          {:reply, {:error, :session_not_found}, state}
      end
    else
      {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call({:delete_session, session_id}, _from, state) do
    cond do
      not Map.has_key?(state.sessions, session_id) ->
        {:reply, {:error, :session_not_found}, state}

      map_size(state.sessions) == 1 ->
        {:reply, {:error, :cannot_delete_last_session}, state}

      true ->
        _ = stop_session_server(session_id)
        _ = SessionMemoryStore.delete_session(session_id)

        state = %{
          state
          | sessions: Map.delete(state.sessions, session_id)
        }

        state =
          if state.current_session_id == session_id do
            %{
              state
              | current_session_id: Session.pick_next_session_id(state.sessions)
            }
          else
            state
          end

        {:reply, {:ok, state.current_session_id}, state}
    end
  end

  @impl true
  def handle_call(:current_history, _from, state) do
    reply =
      case call_session(state.current_session_id, :current_history) do
        {:ok, history} -> history
        {:error, :session_not_found} -> []
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call(:current_mode, _from, state) do
    mode =
      case call_session(state.current_session_id, :current_mode) do
        {:ok, current_mode} -> current_mode
        {:error, :session_not_found} -> :normal
      end

    {:reply, mode, state}
  end

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    case call_session(state.current_session_id, {:set_mode, mode}) do
      {:ok, :ok} ->
        {:reply, :ok, state}

      {:error, :session_not_found} ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call(:current_plan, _from, state) do
    plan =
      case call_session(state.current_session_id, :current_plan) do
        {:ok, value} -> value
        {:error, :session_not_found} -> %{"status" => "idle", "tasks" => []}
      end

    {:reply, plan, state}
  end

  @impl true
  def handle_call(:apply_plan, _from, state) do
    reply =
      case call_session(state.current_session_id, :apply_plan) do
        {:ok, value} -> value
        {:error, :session_not_found} -> {:error, :session_not_found}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call(:reset_plan, _from, state) do
    reply =
      case call_session(state.current_session_id, :reset_plan) do
        {:ok, value} -> value
        {:error, :session_not_found} -> {:error, :session_not_found}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:update_plan, plan}, _from, state) do
    reply =
      case call_session(state.current_session_id, {:update_plan, plan}) do
        {:ok, value} -> value
        {:error, :session_not_found} -> {:error, :session_not_found}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call(:plan_progress, _from, state) do
    progress =
      case call_session(state.current_session_id, :plan_progress) do
        {:ok, value} ->
          value

        {:error, :session_not_found} ->
          %{"done" => 0, "total" => 0, "tasks" => []}
      end

    {:reply, progress, state}
  end

  @impl true
  def handle_call(:current_token_usage, _from, state) do
    usage =
      case call_session(
             state.current_session_id,
             :current_token_usage
           ) do
        {:ok, value} ->
          value

        {:error, :session_not_found} ->
          Usage.default_token_usage_total()
      end

    {:reply, usage, state}
  end

  @impl true
  def handle_call({:run_agent_step, user_input}, _from, state) do
    reply =
      case call_session(
             state.current_session_id,
             {:run_agent_step, user_input},
             300_000
           ) do
        {:ok, result} ->
          result

        {:error, :session_not_found} ->
          step_usage =
            Usage.build_step_usage(
              nil,
              Usage.default_token_usage_total()
            )

          {:done, "当前 session 不存在，请先 /new 后再继续。", step_usage}
      end

    {:reply, reply, state}
  end

  defp start_session_server(session_id, history \\ nil) do
    opts =
      if is_list(history) do
        [session_id: session_id, history: history]
      else
        [session_id: session_id]
      end

    child_spec = {SessionServer, opts}

    case DynamicSupervisor.start_child(SessionSupervisor, child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp stop_session_server(session_id) do
    case lookup_session_pid(session_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end
  end

  defp session_alive?(session_id) do
    case lookup_session_pid(session_id) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp lookup_session_pid(session_id) do
    case Registry.lookup(LightAgent.Core.SessionRegistry, session_id) do
      [{pid, _value}] -> pid
      _ -> nil
    end
  end

  defp call_session(session_id, message, timeout \\ 300_000) do
    try do
      {:ok,
       GenServer.call(
         SessionServer.via_tuple(session_id),
         message,
         timeout
       )}
    catch
      :exit, _ -> {:error, :session_not_found}
    end
  end

  defp restore_or_boot_sessions do
    restored =
      SessionMemoryStore.list_session_ids()
      |> Enum.reduce(%{}, fn session_id, acc ->
        case SessionMemoryStore.load_session(session_id) do
          {:ok, history} when is_list(history) ->
            case start_session_server(session_id, history) do
              :ok -> Map.put(acc, session_id, %{status: :active})
              {:error, _} -> acc
            end

          _ ->
            acc
        end
      end)

    if map_size(restored) > 0 do
      current_session_id =
        if Map.has_key?(restored, "init") do
          "init"
        else
          restored |> Map.keys() |> Enum.sort() |> List.first()
        end

      {:ok, %{current_session_id: current_session_id, sessions: restored}}
    else
      session_id = "init"

      case start_session_server(session_id) do
        :ok ->
          {:ok,
           %{
             current_session_id: session_id,
             sessions: %{session_id => %{status: :active}}
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp new_session_id do
    Ecto.UUID.generate()
  end
end
