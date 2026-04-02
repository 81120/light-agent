defmodule LightAgent.Core.Skill.FsBasedSkill do
  alias LightAgent.Core.AgentPaths

  def list_skills do
    AgentPaths.skills_root()
    |> list_skills_from_root()
  end

  def load_skills() do
    skills_meta =
      list_skills()
      |> Enum.map(fn %{name: name, description: description} ->
        %{
          skill_name: name,
          skill_description: description
        }
      end)
      |> Jason.encode!()

    """
    你可以使用#{AgentPaths.skills_root()}目录下的以下工具来回答问题：
    #{skills_meta}
    你可以在需要的时候读取对应skill目录下的SKILL.md文件，来获取该工具的详细描述和使用方式。
    """
  end

  def load_skill(skill_dir) do
    AgentPaths.skills_root()
    |> load_skill_from_root(skill_dir)
  end

  defp list_skills_from_root(skills_root) do
    if File.dir?(skills_root) do
      skills_root
      |> File.ls!()
      |> Enum.map(&parse_skill_meta(skills_root, &1))
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp load_skill_from_root(skills_root, skill_dir) do
    skill_meta_file = Path.join(skills_root, "#{skill_dir}/SKILL.md")

    if File.exists?(skill_meta_file) do
      content = File.read!(skill_meta_file)
      regex = ~r/\A\s*---(?s)(.*?)^---/m

      case Regex.run(regex, content, capture: :all_but_first) do
        [yaml_content] ->
          name =
            yaml_content |> extract_yaml_value("name") || skill_dir

          description =
            yaml_content
            |> extract_yaml_value("description")
            |> case do
              nil -> String.trim(yaml_content)
              value -> value
            end

          %{
            name: String.trim(name),
            description: String.trim(description)
          }

        nil ->
          nil
      end
    else
      nil
    end
  end

  defp parse_skill_meta(skills_root, skill_dir) do
    load_skill_from_root(skills_root, skill_dir)
  end

  defp extract_yaml_value(yaml_content, key) do
    regex = ~r/(?:^|\n)\s*#{key}:\s*(.+?)\s*(?:\n|$)/

    case Regex.run(regex, yaml_content, capture: :all_but_first) do
      [value] -> String.trim(value, "\"'")
      _ -> nil
    end
  end
end
