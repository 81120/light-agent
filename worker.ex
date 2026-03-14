defmodule Toyagent.Core.Worker do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def run_agent(user_input \\ nil) do
    res = GenServer.call(__MODULE__, {:run_agent, user_input}, 60_000)

    case res do
      {:running, _tool_results} ->
        run_agent()

      {:done, content} ->
        Logger.debug("Agent 完成任务：#{content}")
        content
    end
  end

  @impl true
  def init(_opts) do
    Toyagent.Core.Memory.LongTerm.add_items([
      %{
        role: "system",
        content: "你是一个有用的 AI 助手，你可以使用工具来回答问题，有内置的tools和基于文件系统的skills。"
      },
      %{
        role: "system",
        content: Toyagent.Core.Skill.FsBasedSkill.load_skills()
      }
    ])

    {:ok, %{}}
  end

  @impl true
  def handle_call({:run_agent, user_input}, _from, state) do
    if user_input do
      Toyagent.Core.Memory.ShortTerm.add_item(%{
        role: "user",
        content: user_input
      })
    end

    history = Toyagent.Core.Memory.All.get()
    tools = Toyagent.Core.Skill.Runner.build_tools_schema()
    response = Toyagent.Core.LLM.call(history, tools)
    message = response["choices"] |> List.first() |> get_in(["message"])

    case message do
      %{"tool_calls" => tool_calls} when is_list(tool_calls) ->
        tool_results = Toyagent.Core.Skill.Runner.handle_tool_call(tool_calls)
        Toyagent.Core.Memory.ShortTerm.add_item(message)
        Toyagent.Core.Memory.ShortTerm.add_items(tool_results)

        {:reply, {:running, tool_results}, state}

      %{"content" => content} ->
        {:reply, {:done, content}, state}
    end
  end
end
