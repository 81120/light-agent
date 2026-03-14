defmodule LightAgent.Core.Skill.FsBasedSkill do
  @root_dir_of_skills "./.agent/skills/"

  def load_skills() do
    skills_meta =
      @root_dir_of_skills
      |> File.ls!()
      |> Enum.map(&parse_skill_meta/1)
      |> Enum.filter(&(&1 != nil))
      |> Jason.encode!()

    """
    你可以使用.agent/skills目录下的以下工具来回答问题：
    #{skills_meta}
    你可以在需要的时候读取对应skill目录下的SKILL.md文件，来获取该工具的详细描述和使用方式。
    """
  end

  defp parse_skill_meta(skill_dir) do
    skill_meta_file = Path.join(@root_dir_of_skills, "#{skill_dir}/SKILL.md")

    if File.exists?(skill_meta_file) do
      content = File.read!(skill_meta_file)
      regex = ~r/\A\s*---(?s)(.*?)^---/m

      case Regex.run(regex, content, capture: :all_but_first) do
        [yaml_content] ->
          String.trim(yaml_content)

          %{
            skill_name: skill_dir,
            skill_description: yaml_content
          }

        nil ->
          nil
      end
    else
      nil
    end
  end
end
