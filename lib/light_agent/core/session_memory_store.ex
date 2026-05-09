defmodule LightAgent.Core.SessionMemoryStore do
  alias LightAgent.Core.AgentPaths
  alias LightAgent.Core.Worker.Usage

  @json_block_regex ~r/```json\n([\s\S]*?)\n```/

  def list_session_ids do
    AgentPaths.session_memory_root()
    |> Path.join("session-*.md")
    |> Path.wildcard()
    |> Enum.map(&session_id_from_path/1)
    |> Enum.reject(&is_nil/1)
  end

  def load_session(session_id) do
    case load_session_data(session_id) do
      {:ok, %{"history" => history}} -> {:ok, history}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_session_data(session_id) do
    case load_session_payload(session_id) do
      {:ok, %{"history" => history} = payload} when is_list(history) ->
        {:ok, normalize_loaded_payload(payload)}

      {:ok, _payload} ->
        {:error, :invalid_format}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def load_session_payload(session_id) do
    file_path = AgentPaths.session_memory_file_path(session_id)

    case File.read(file_path) do
      {:ok, content} -> parse_markdown_payload(content)
      {:error, reason} -> {:error, reason}
    end
  end

  def persist_session(session_id, history) when is_list(history) do
    persist_session(session_id, history, Usage.default_token_usage_total())
  end

  def persist_session(session_id, history, token_usage_total)
      when is_list(history) and is_map(token_usage_total) do
    payload = %{
      "session_id" => session_id,
      "updated_at" =>
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601(),
      "history" => history,
      "token_usage_total" => token_usage_total
    }

    persist_session_payload(payload)
  end

  def persist_session_payload(
        %{"session_id" => session_id, "history" => history} = payload
      )
      when is_binary(session_id) and is_list(history) do
    payload =
      payload
      |> Map.put_new_lazy("updated_at", fn ->
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
      end)
      |> Map.put_new("token_usage_total", Usage.default_token_usage_total())
      |> normalize_for_persist()

    file_path = AgentPaths.session_memory_file_path(session_id)

    with :ok <- File.mkdir_p(AgentPaths.session_memory_root()),
         {:ok, json} <- Jason.encode(payload, pretty: true),
         markdown = to_markdown(session_id, json),
         :ok <- write_if_changed(file_path, markdown, payload) do
      :ok
    end
  end

  def persist_session_payload(_payload),
    do: {:error, :invalid_payload}

  def delete_session(session_id) do
    case File.rm(AgentPaths.session_memory_file_path(session_id)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp session_id_from_path(path) do
    path
    |> Path.basename(".md")
    |> case do
      "session-" <> session_id -> session_id
      _ -> nil
    end
  end

  defp to_markdown(session_id, json) do
    [
      "# Session ",
      session_id,
      "\n\n",
      "```json\n",
      json,
      "\n```\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp parse_markdown_payload(content) do
    case Regex.run(@json_block_regex, content) do
      [_, json] ->
        case Jason.decode(json) do
          {:ok, payload} when is_map(payload) -> {:ok, payload}
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp normalize_for_persist(payload) do
    payload
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp normalize_loaded_payload(payload) do
    token_usage_total =
      payload
      |> Map.get("token_usage_total")
      |> normalize_token_usage_total()

    Map.put(payload, "token_usage_total", token_usage_total)
  end

  defp normalize_token_usage_total(raw) when is_map(raw) do
    default = Usage.default_token_usage_total()

    %{
      prompt_tokens:
        normalize_usage_counter(raw, :prompt_tokens, default.prompt_tokens),
      completion_tokens:
        normalize_usage_counter(
          raw,
          :completion_tokens,
          default.completion_tokens
        ),
      total_tokens:
        normalize_usage_counter(raw, :total_tokens, default.total_tokens),
      steps: normalize_usage_counter(raw, :steps, default.steps),
      missing_usage_steps:
        normalize_usage_counter(
          raw,
          :missing_usage_steps,
          default.missing_usage_steps
        )
    }
  end

  defp normalize_token_usage_total(_), do: Usage.default_token_usage_total()

  defp normalize_usage_counter(raw, key, default) do
    value = Map.get(raw, key) || Map.get(raw, Atom.to_string(key))

    case value do
      n when is_integer(n) ->
        n

      n when is_float(n) ->
        trunc(n)

      n when is_binary(n) ->
        case Integer.parse(n) do
          {parsed, ""} -> parsed
          _ -> default
        end

      _ ->
        default
    end
  end

  defp write_if_changed(file_path, markdown, payload) do
    case File.read(file_path) do
      {:ok, existing_markdown} ->
        case parse_markdown_payload(existing_markdown) do
          {:ok, existing_payload} ->
            if equivalent_payload_content?(existing_payload, payload) do
              :ok
            else
              File.write(file_path, markdown)
            end

          _ ->
            File.write(file_path, markdown)
        end

      {:error, :enoent} ->
        File.write(file_path, markdown)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp equivalent_payload_content?(left, right) do
    Map.drop(left, ["updated_at"]) == Map.drop(right, ["updated_at"])
  end
end
