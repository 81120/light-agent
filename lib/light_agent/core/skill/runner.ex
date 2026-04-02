defmodule LightAgent.Core.Skill.Runner do
  require Logger

  alias LightAgent.Core.Skill.SchemaJsonSchema
  alias LightAgent.Core.Skill.ToolArgsValidator

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
            parameters: tool_parameters(tool)
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
        args = decode_tool_arguments(call)
        result = dispatch_tool(function_name, args)

        %{
          tool_call_id: call["id"],
          role: "tool",
          name: function_name,
          content: result
        }
      end,
      max_concurrency: 10,
      timeout: 300_000
    )
    |> Enum.to_list()
    |> Enum.map(fn {:ok, res} -> res end)
  end

  defp tool_parameters(tool) do
    tool
    |> Map.fetch!(:param_schema)
    |> SchemaJsonSchema.to_json_schema()
  end

  defp decode_tool_arguments(call) do
    arguments = get_in(call, ["function", "arguments"])

    case Jason.decode(arguments || "{}") do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp dispatch_tool(function_name, args) do
    with {:ok, {skill_module, tool}} <- resolve_tool(function_name),
         {:ok, validated_args} <-
           ToolArgsValidator.validate(tool, args) do
      apply(skill_module, tool.function, [validated_args])
    else
      {:error, :tool_not_found} ->
        "工具 #{function_name} 不存在"

      {:error, validation_error} when is_map(validation_error) ->
        Jason.encode!(validation_error)
    end
  end

  defp resolve_tool(function_name) do
    result =
      Enum.find_value(list_skills(), fn skill_module ->
        tools = skill_module.__skill_definition__().tools

        tool =
          Enum.find(
            tools,
            &(Atom.to_string(&1.name) == function_name)
          )

        if tool do
          {skill_module, tool}
        end
      end)

    if result, do: {:ok, result}, else: {:error, :tool_not_found}
  end
end
