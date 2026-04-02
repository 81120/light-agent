defmodule LightAgent.Skills.LoadFsSkill do
  use LightAgent.Core.Skill.CodeBasedSkill

  alias LightAgent.Core.AgentPaths

  defmodule LoadSkillMdParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:skill_name, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:skill_name])
      |> validate_required([:skill_name])
    end

    def required_fields, do: [:skill_name]
  end

  @doc "加载指定的基于文件系统的skill的SKILL.md文件的内容"
  deftool(:load_skill_md, schema: LoadSkillMdParams)

  def exec(:load_skill_md, %{"skill_name" => skill_name}) do
    skill_path =
      Path.join([AgentPaths.skills_root(), skill_name, "SKILL.md"])

    case File.read(skill_path) do
      {:ok, content} ->
        content

      {:error, reason} ->
        "读取skill #{skill_name} 的SKILL.md文件失败: #{inspect(reason)}"
    end
  end
end
