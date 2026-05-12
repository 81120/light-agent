defmodule LightAgent.Dashboard do
  alias LightAgent.Core.AgentPaths
  alias LightAgent.Core.SessionMemoryStore
  alias LightAgent.Core.Skill.FsBasedSkill
  alias LightAgent.Core.Skill.Runner
  alias LightAgent.Core.Worker

  def list_sessions do
    Worker.list_sessions()
    |> Enum.map(&enrich_session_summary/1)
  end

  def get_session_detail(session_id) when is_binary(session_id) do
    with {:ok, detail} <- Worker.session_detail(session_id) do
      {:ok, Map.merge(detail, payload_metadata(session_id))}
    end
  end

  def get_session_detail(_), do: {:error, :invalid_session_id}

  def get_session_history(session_id) when is_binary(session_id) do
    Worker.session_history(session_id)
  end

  def get_session_history(_), do: {:error, :invalid_session_id}

  def send_session_message(session_id, content)
      when is_binary(session_id) and is_binary(content) do
    trimmed = String.trim(content)

    cond do
      trimmed == "" ->
        {:error, :empty_message}

      Worker.session_detail(session_id) == {:error, :session_not_found} ->
        {:error, :session_not_found}

      true ->
        {:ok, run_session_until_done(session_id, trimmed)}
    end
  end

  def send_session_message(_session_id, _content),
    do: {:error, :invalid_input}

  def switch_session(session_id) when is_binary(session_id) do
    Worker.switch_session(session_id)
  end

  def switch_session(_), do: {:error, :invalid_session_id}

  def get_effective_global_context do
    context_files =
      AgentPaths.context_file_paths()
      |> Enum.map(fn path ->
        content = read_context_file(path)

        %{
          name: Path.basename(path),
          path: path,
          content: content,
          loaded: content != nil
        }
      end)

    %{
      context_files: context_files,
      skills: list_skills(),
      tools: list_tools(),
      dynamic_skills_context: FsBasedSkill.load_skills()
    }
  end

  defp enrich_session_summary(%{id: id} = session) do
    Map.merge(session, payload_metadata(id))
  end

  defp list_skills do
    FsBasedSkill.list_skills()
    |> Enum.map(fn %{name: name, description: description} ->
      %{name: name, description: normalize_description(description)}
    end)
  end

  defp list_tools do
    Runner.list_skills()
    |> Enum.flat_map(fn skill_module ->
      definition = skill_module.__skill_definition__()

      Enum.map(definition.tools, fn tool ->
        %{
          name: tool.name |> to_string(),
          description: normalize_description(tool.description)
        }
      end)
    end)
  end

  defp normalize_description(description)
       when is_binary(description) do
    description
    |> String.trim()
    |> case do
      "" -> "No description"
      value -> value
    end
  end

  defp normalize_description(_), do: "No description"

  defp payload_metadata(session_id) do
    case SessionMemoryStore.load_session_payload(session_id) do
      {:ok, %{"updated_at" => updated_at, "history" => history}}
      when is_list(history) ->
        %{updated_at: updated_at, history_count: length(history)}

      {:ok, %{"updated_at" => updated_at}} ->
        %{updated_at: updated_at, history_count: 0}

      _ ->
        %{updated_at: nil, history_count: 0}
    end
  end

  defp read_context_file(path) do
    case File.read(path) do
      {:ok, content} ->
        trimmed = String.trim(content)
        if trimmed == "", do: nil, else: trimmed

      {:error, _} ->
        nil
    end
  end

  defp run_session_until_done(session_id, user_input) do
    case Worker.run_agent_step_for_session(session_id, user_input) do
      {:running, _tool_results, _step_usage} ->
        run_session_until_done(session_id, nil)

      {:done, _reply, _step_usage} = result ->
        result
    end
  end
end
