defmodule LightAgent.Core.SessionServer do
  use GenServer

  alias LightAgent.Core.SessionMemoryStore
  alias LightAgent.Core.Worker.Session
  alias LightAgent.Core.Worker.Usage

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  def via_tuple(session_id),
    do: {:via, Registry, {LightAgent.Core.SessionRegistry, session_id}}

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    history =
      Keyword.get(opts, :history, Session.new_session_data().history)

    state = %{
      id: session_id,
      status: :active,
      mode: :normal,
      plan_state: default_plan_state(),
      history: history,
      token_usage_total: Usage.default_token_usage_total(),
      tool_retry_count: 0
    }

    persist_history(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, %{id: state.id, status: state.status}, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | status: :paused}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    {:reply, :ok, %{state | status: :active}}
  end

  @impl true
  def handle_call(:current_history, _from, state) do
    {:reply, state.history, state}
  end

  @impl true
  def handle_call(:current_mode, _from, state) do
    {:reply, state.mode, state}
  end

  @impl true
  def handle_call({:set_mode, :normal}, _from, state) do
    {:reply, :ok, %{state | mode: :normal}}
  end

  @impl true
  def handle_call({:set_mode, :plan}, _from, state) do
    plan_state =
      default_plan_state()
      |> Map.put("status", "drafting")

    state = %{state | mode: :plan, plan_state: plan_state} |> persist_history()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:current_plan, _from, state) do
    {:reply, state.plan_state, state}
  end

  @impl true
  def handle_call(:apply_plan, _from, state) do
    tasks = Map.get(state.plan_state, "tasks", [])

    if tasks == [] do
      {:reply, {:error, :empty_plan}, state}
    else
      state =
        state
        |> put_in([:plan_state, "status"], "applying")
        |> mark_first_pending_in_progress()
        |> persist_history()

      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:reset_plan, _from, state) do
    state = %{state | plan_state: default_plan_state()} |> persist_history()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:update_plan, plan}, _from, state) when is_map(plan) do
    next_plan =
      state.plan_state
      |> Map.merge(plan)
      |> Map.update("revision", 1, &(&1 + 1))
      |> normalize_plan_tasks()

    state = %{state | plan_state: next_plan} |> persist_history()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:plan_progress, _from, state) do
    tasks = Map.get(state.plan_state, "tasks", [])

    done = Enum.count(tasks, &(&1["status"] == "done"))
    total = length(tasks)
    status = Map.get(state.plan_state, "status", "idle")

    {:reply,
     %{"status" => status, "done" => done, "total" => total, "tasks" => tasks},
     state}
  end

  @impl true
  def handle_call(:current_token_usage, _from, state) do
    {:reply, state.token_usage_total, state}
  end

  @impl true
  def handle_call({:run_agent_step, user_input}, _from, state) do
    {reply, state} = run_agent_step_internal(user_input, state)
    {:reply, reply, state}
  end

  defp llm_call_opts() do
    case Application.get_env(:LightAgent, :llm_request_fun) do
      nil -> []
      request_fun -> [request_fun: request_fun]
    end
  end

  defp run_agent_step_internal(user_input, state) do
    if state.status == :paused do
      step_usage =
        Usage.build_step_usage(nil, state.token_usage_total)

      {{:done, "当前 session 已暂停，请先 /resume 后再继续。", step_usage}, state}
    else
      state =
        if user_input do
          state
          |> update_in([:history], fn history ->
            Session.append_history(history, %{
              role: "user",
              content: user_input
            })
          end)
          |> Map.put(:tool_retry_count, 0)
          |> persist_history()
        else
          state
        end

      tools = LightAgent.Core.Skill.Runner.build_tools_schema()

      case LightAgent.Core.LLM.call(
             state.history,
             tools,
             llm_call_opts()
           ) do
        {:ok, response} ->
          handle_llm_response(response, state)

        {:error, _reason, message} ->
          step_usage =
            Usage.build_step_usage(nil, state.token_usage_total)

          {{:done, message, step_usage}, state}
      end
    end
  end

  defp handle_llm_response(response, state) do
    usage = Usage.extract_usage(response)

    token_total =
      Usage.update_token_usage(state.token_usage_total, usage)

    step_usage = Usage.build_step_usage(usage, token_total)
    state = %{state | token_usage_total: token_total}

    message =
      response
      |> Map.get("choices", [])
      |> List.first()
      |> case do
        %{"message" => msg} -> msg
        _ -> nil
      end

    case message do
      %{"tool_calls" => tool_calls} when is_list(tool_calls) ->
        plan_phase =
          if state.mode == :plan and plan_in_drafting_phase?(state.plan_state),
            do: :draft,
            else: :apply

        tool_results =
          LightAgent.Core.Skill.Runner.handle_tool_call(
            tool_calls,
            mode: state.mode,
            plan_phase: plan_phase
          )

        state =
          state
          |> update_in([:history], fn history ->
            Session.append_history(history, message)
          end)
          |> update_in([:history], fn history ->
            Session.append_history_list(history, tool_results)
          end)
          |> maybe_advance_plan_progress()
          |> persist_history()

        if has_validation_error?(tool_results) and
             state.tool_retry_count < 1 do
          retry_state =
            state
            |> update_in([:history], fn history ->
              Session.append_history(history, %{
                role: "system",
                content: build_validation_retry_prompt(tool_results)
              })
            end)
            |> Map.put(:tool_retry_count, state.tool_retry_count + 1)
            |> persist_history()

          run_agent_step_internal(nil, retry_state)
        else
          {{:running, tool_results, step_usage}, state}
        end

      %{"content" => content} when is_binary(content) ->
        state =
          state
          |> update_in([:history], fn history ->
            Session.append_history(history, message)
          end)
          |> maybe_capture_plan_from_content(content)
          |> maybe_advance_plan_progress()
          |> persist_history()

        {{:done, content, step_usage}, state}

      _ ->
        {{:done, "LLM 返回异常，请稍后重试。", step_usage}, state}
    end
  end

  defp has_validation_error?(tool_results) do
    Enum.any?(tool_results, fn result ->
      content =
        Map.get(result, :content) || Map.get(result, "content") || ""

      case Jason.decode(content) do
        {:ok, %{"type" => "validation_error"}} -> true
        _ -> false
      end
    end)
  end

  defp build_validation_retry_prompt(tool_results) do
    errors =
      tool_results
      |> Enum.map(fn result ->
        content =
          Map.get(result, :content) || Map.get(result, "content") ||
            ""

        case Jason.decode(content) do
          {:ok, %{"type" => "validation_error"} = payload} ->
            format_validation_error(payload)

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    [
      "你上一次 tool 调用参数不合法，请仅修正参数后重新调用对应工具。",
      Enum.join(errors, "\n")
    ]
    |> Enum.join("\n")
  end

  defp format_validation_error(%{"tool" => tool, "errors" => errors}) do
    detail =
      errors
      |> Enum.map(fn %{"field" => field, "message" => message} ->
        "#{field}: #{message}"
      end)
      |> Enum.join("; ")

    "tool=#{tool} 参数错误: #{detail}"
  end

  defp persist_history(state) do
    _ = SessionMemoryStore.persist_session(state.id, state.history)
    state
  end

  defp default_plan_state do
    %{
      "status" => "idle",
      "title" => nil,
      "tasks" => [],
      "raw_plan" => nil,
      "revision" => 0
    }
  end

  defp normalize_plan_tasks(plan_state) do
    tasks =
      plan_state
      |> Map.get("tasks", [])
      |> Enum.with_index(1)
      |> Enum.map(fn {task, idx} ->
        %{
          "id" => Map.get(task, "id", "T#{idx}"),
          "text" => Map.get(task, "text", ""),
          "status" => Map.get(task, "status", "pending"),
          "note" => Map.get(task, "note")
        }
      end)

    Map.put(plan_state, "tasks", tasks)
  end

  defp maybe_capture_plan_from_content(state, content) do
    if state.mode == :plan and plan_in_drafting_phase?(state.plan_state) do
      case decode_plan_payload(content) do
        {:ok, %{"title" => title, "tasks" => tasks}}
        when is_list(tasks) and tasks != [] ->
          plan_state =
            state.plan_state
            |> Map.put("status", "ready")
            |> Map.put("title", title)
            |> Map.put("tasks", tasks)
            |> Map.put("raw_plan", content)
            |> Map.update("revision", 1, &(&1 + 1))
            |> normalize_plan_tasks()

          %{state | plan_state: plan_state}

        _ ->
          state
      end
    else
      state
    end
  end

  defp decode_plan_payload(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, payload} ->
        {:ok, payload}

      _ ->
        content
        |> extract_json_block()
        |> case do
          nil -> :error
          json -> Jason.decode(json)
        end
    end
  end

  defp decode_plan_payload(_), do: :error

  defp extract_json_block(content) do
    Regex.run(~r/```(?:json)?\s*(\{[\s\S]*\})\s*```/i, content,
      capture: :all_but_first
    )
    |> case do
      [json] -> json
      _ -> nil
    end
  end

  defp plan_in_drafting_phase?(plan_state) do
    Map.get(plan_state, "status", "idle") in ["idle", "drafting", "ready"]
  end

  defp maybe_advance_plan_progress(state) do
    if state.mode == :plan and Map.get(state.plan_state, "status") == "applying" do
      tasks = Map.get(state.plan_state, "tasks", [])

      {updated, changed?} =
        cond do
          Enum.any?(tasks, &(&1["status"] == "in_progress")) ->
            done_marked =
              Enum.map(tasks, fn task ->
                if task["status"] == "in_progress",
                  do: Map.put(task, "status", "done"),
                  else: task
              end)

            promoted =
              if Enum.any?(done_marked, &(&1["status"] == "pending")) do
                mark_next_pending_in_progress(done_marked)
              else
                done_marked
              end

            {promoted, true}

          Enum.any?(tasks, &(&1["status"] == "pending")) ->
            {
              mark_next_pending_in_progress(tasks),
              true
            }

          true ->
            {tasks, false}
        end

      plan_state =
        state.plan_state
        |> Map.put("tasks", updated)
        |> then(fn plan ->
          cond do
            Enum.all?(updated, &(&1["status"] == "done")) and updated != [] ->
              Map.put(plan, "status", "completed")

            Enum.any?(updated, &(&1["status"] == "in_progress")) ->
              Map.put(plan, "status", "applying")

            true ->
              plan
          end
        end)

      if changed?, do: %{state | plan_state: plan_state}, else: state
    else
      state
    end
  end

  defp mark_first_pending_in_progress(state) do
    tasks = Map.get(state.plan_state, "tasks", [])

    updated =
      if Enum.any?(tasks, &(&1["status"] == "in_progress")) do
        tasks
      else
        mark_next_pending_in_progress(tasks)
      end

    put_in(state, [:plan_state, "tasks"], updated)
  end

  defp mark_next_pending_in_progress(tasks) do
    {updated, _} =
      Enum.map_reduce(tasks, false, fn task, promoted ->
        if not promoted and task["status"] == "pending" do
          {Map.put(task, "status", "in_progress"), true}
        else
          {task, promoted}
        end
      end)

    updated
  end
end
