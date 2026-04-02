defmodule LightAgent.Core.SessionMemoryStore do
  alias LightAgent.Core.AgentPaths

  @json_block_regex ~r/```json\n([\s\S]*?)\n```/

  def list_session_ids do
    AgentPaths.session_memory_root()
    |> Path.join("session-*.md")
    |> Path.wildcard()
    |> Enum.map(&session_id_from_path/1)
    |> Enum.reject(&is_nil/1)
  end

  def load_session(session_id) do
    case load_session_payload(session_id) do
      {:ok, %{"history" => history}} when is_list(history) ->
        {:ok, history}

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
    payload = %{
      "session_id" => session_id,
      "updated_at" =>
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601(),
      "history" => history
    }

    persist_session_payload(payload)
  end

  def persist_session_payload(
        %{"session_id" => session_id, "history" => history} = payload
      )
      when is_binary(session_id) and is_list(history) do
    payload =
      Map.put_new_lazy(payload, "updated_at", fn ->
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
      end)

    with :ok <- File.mkdir_p(AgentPaths.session_memory_root()),
         {:ok, json} <- Jason.encode(payload, pretty: true),
         :ok <-
           File.write(
             AgentPaths.session_memory_file_path(session_id),
             to_markdown(session_id, json)
           ) do
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
end
