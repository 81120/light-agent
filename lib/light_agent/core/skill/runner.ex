defmodule LightAgent.Core.Skill.Runner do
  require Logger

  @moduledoc "运行器，负责管理和执行任务"
  def list_skills do
    [
      LightAgent.Skills.Location,
      LightAgent.Skills.Weather,
      LightAgent.Skills.Filesystem,
      LightAgent.Skills.RunCommand,
      LightAgent.Skills.LoadFsSkill
    ]
  end

  def build_tools_schema do
    Enum.flat_map(list_skills(), fn skill_module ->
      definition = skill_module.__skill_definition__()

      Enum.map(definition.tools, fn tool ->
        %{
          type: "function",
          function: %{
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters
          }
        }
      end)
    end)
  end

  def handle_tool_call(tool_call) do
    tool_call
    |> Task.async_stream(
      fn call ->
        function_name = call["function"]["name"]
        args = Jason.decode!(call["function"]["arguments"])
        result = dispatch_tool(function_name, args)

        %{
          tool_call_id: call["id"],
          role: "tool",
          name: function_name,
          content: result
        }
      end,
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Enum.to_list()
    |> Enum.map(fn {:ok, res} -> res end)
  end

  defp dispatch_tool(function_name, args) do
    Enum.find_value(list_skills(), fn skill_module ->
      tools = skill_module.__skill_definition__().tools
      tool = Enum.find(tools, &(Atom.to_string(&1.name) == function_name))

      if tool do
        apply(skill_module, tool.function, [args])
      else
        nil
      end
    end)
  end
end
