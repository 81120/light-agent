defmodule LightAgent.Skills.RunCommand do
  @moduledoc "提供运行命令能力的技能包"

  use LightAgent.Core.Skill.CodeBasedSkill

  defmodule RunCommandParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:command, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:command])
      |> validate_required([:command])
    end

    def required_fields, do: [:command]
  end

  @doc "运行指定命令"
  deftool(:run_command, schema: RunCommandParams)

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
