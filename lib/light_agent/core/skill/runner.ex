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

  def handle_tool_call(tool_call, opts \\ []) do
    mode = Keyword.get(opts, :mode, :normal)
    plan_phase = Keyword.get(opts, :plan_phase, :apply)

    Enum.map(tool_call, fn call ->
      function_name = call["function"]["name"]
      args = decode_tool_arguments(call)
      result = dispatch_tool(function_name, args, mode, plan_phase)

      %{
        tool_call_id: call["id"],
        role: "tool",
        name: function_name,
        content: result
      }
    end)
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

  defp dispatch_tool(function_name, _args, :plan, :draft) do
    Jason.encode!(%{
      "type" => "plan_mode_blocked",
      "tool" => function_name,
      "message" => "plan mode 下未 apply 计划，禁止执行工具"
    })
  end

  defp dispatch_tool(function_name, args, :plan, :apply) do
    dispatch_tool(function_name, args, :normal, :apply)
  end

  defp dispatch_tool(function_name, args, :normal, _plan_phase) do
    with {:ok, {skill_module, tool}} <- resolve_tool(function_name),
         {:ok, validated_args} <-
           ToolArgsValidator.validate(tool, args) do
      if requires_user_confirmation?(function_name) do
        case request_user_confirmation(function_name, validated_args) do
          :allow ->
            apply(skill_module, tool.function, [validated_args])

          :deny ->
            Jason.encode!(%{
              "type" => "permission_denied",
              "tool" => function_name,
              "message" => "用户拒绝执行该操作"
            })
        end
      else
        apply(skill_module, tool.function, [validated_args])
      end
    else
      {:error, :tool_not_found} ->
        "工具 #{function_name} 不存在"

      {:error, validation_error} when is_map(validation_error) ->
        Jason.encode!(validation_error)
    end
  end

  defp requires_user_confirmation?(function_name)
       when is_binary(function_name) do
    function_name in [
      "run_command",
      "write_file",
      "delete_file",
      "remove_file"
    ]
  end

  defp request_user_confirmation(function_name, args) do
    case LightAgent.CLI.Prompts.confirm_tool_execution(function_name, args) do
      :allow -> :allow
      :deny -> :deny
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
