defmodule LightAgent.CLI.Prompts do
  @moduledoc false

  @spec confirm_tool_execution(String.t(), map()) :: :allow | :deny
  def confirm_tool_execution(function_name, args)
      when is_binary(function_name) and is_map(args) do
    args_json = Jason.encode!(args)

    case Prompt.confirm(
           "Approve to execute #{function_name} with args #{args_json} ?",
           default_answer: :no
         ) do
      :yes -> :allow
      :no -> :deny
    end
  rescue
    _ -> :deny
  end
end
