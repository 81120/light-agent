defmodule LightAgent.Core.Worker.Session do
  alias LightAgent.Core.AgentPaths

  def session_sort_key(%{id: id}) when is_binary(id), do: id

  def session_sort_key(_), do: "~"

  def pick_next_session_id(sessions) do
    sessions
    |> Map.keys()
    |> Enum.sort_by(fn id -> session_sort_key(%{id: id}) end)
    |> List.first()
  end

  def append_history(history, item), do: history ++ [item]

  def append_history_list(history, items), do: history ++ items

  def new_session_data() do
    %{
      status: :active,
      history:
        load_agent_config_system_prompts() ++
          [
            %{
              role: "system",
              content: LightAgent.Core.Skill.FsBasedSkill.load_skills()
            }
          ],
      token_usage_total:
        LightAgent.Core.Worker.Usage.default_token_usage_total()
    }
  end

  defp load_agent_config_system_prompts do
    AgentPaths.context_file_paths()
    |> Enum.map(&read_context_file/1)
    |> Enum.reject(&is_nil/1)
  end

  defp read_context_file(file_path) do
    if File.exists?(file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          to_context_system_message(file_path, content)

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp to_context_system_message(file_path, content) do
    trimmed = String.trim(content)

    if trimmed == "" do
      nil
    else
      file_name = Path.basename(file_path)

      %{
        role: "system",
        content: "[agent/config/#{file_name}]\n#{trimmed}"
      }
    end
  end
end
