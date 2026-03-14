defmodule Toyagent.Skills.RunCommand do
  @moduledoc "提供运行命令能力的技能包"

  use Toyagent.Core.Skill.CodeBasedSkill

  @doc "运行指定命令"
  deftool(:run_command, %{
    type: "object",
    properties: %{
      command: %{
        type: "string",
        description: "要运行的命令，如 ls -l"
      }
    },
    required: ["command"]
  })

  @impl true
  def exec(:run_command, %{"command" => command}) do
    case System.cmd("sh", ["-c", command]) do
      {output, 0} ->
        output

      {output, code} ->
        "命令 #{command} 执行失败，退出码 #{code}，输出: #{output}"
    end
  end
end
