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
        tool_results =
          LightAgent.Core.Skill.Runner.handle_tool_call(tool_calls)

        state =
          state
          |> update_in([:history], fn history ->
            Session.append_history(history, message)
          end)
          |> update_in([:history], fn history ->
            Session.append_history_list(history, tool_results)
          end)
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
end
