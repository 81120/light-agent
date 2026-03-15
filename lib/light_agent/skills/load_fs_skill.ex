defmodule LightAgent.Skills.LoadFsSkill do
  @moduledoc """
  加载基于文件系统的skill的SKILL.md文件
  """
  use LightAgent.Core.Skill.CodeBasedSkill

  @skill_dir ".agent/skills/"

  @doc "读取指定的基于文件系统的skill的SKILL.md"
  deftool(:load_fs_skill, %{
    type: "object",
    properties: %{
      skill_name: %{
        type: "string",
        description: "The name of the skill to load"
      }
    },
    required: ["skill_name"]
  })

  @impl true
  def exec(:load_fs_skill, %{"skill_name" => skill_name}) do
    skill_path = Path.join([@skill_dir, skill_name, "SKILL.md"])

    case File.read(skill_path) do
      {:ok, skill_content} ->
        skill_content

      {:error, _} ->
        "Skill #{skill_name} not found"
    end
  end
end
