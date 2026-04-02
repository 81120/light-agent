defmodule LightAgent.Core.SessionMemoryCompactor do
  use GenServer

  require Logger

  alias LightAgent.Core.AgentPaths
  alias LightAgent.Core.SessionMemoryStore

  @default_interval_ms 10 * 60 * 1000
  @min_compaction_messages 100
  @adjacent_window 2
  @managed_start "<!-- session-compaction:start -->"
  @managed_end "<!-- session-compaction:end -->"
  @summary_marker "[compaction/session-summary]"
  @protected_prefixes [
    "[agent/config/SOUL.md]",
    "[agent/config/USER.md]",
    "[agent/config/AGENT.md]",
    "[agent/config/MEMORY.md]"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def run_once do
    GenServer.call(__MODULE__, :run_once, 300_000)
  end

  @impl true
  def init(_opts) do
    interval_ms =
      Application.get_env(
        :LightAgent,
        :session_compaction_interval_ms,
        @default_interval_ms
      )

    schedule_tick(interval_ms)
    {:ok, %{interval_ms: interval_ms}}
  end

  @impl true
  def handle_call(:run_once, _from, state) do
    do_compact_all_sessions()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    do_compact_all_sessions()
    schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  defp schedule_tick(interval_ms) do
    Process.send_after(self(), :tick, interval_ms)
  end

  defp do_compact_all_sessions do
    SessionMemoryStore.list_session_ids()
    |> Enum.reduce([], fn session_id, acc ->
      case SessionMemoryStore.load_session_payload(session_id) do
        {:ok, payload} ->
          case compact_payload(payload) do
            {:changed, updated_payload, session_patterns} ->
              :ok =
                SessionMemoryStore.persist_session_payload(updated_payload)

              [session_patterns | acc]

            {:unchanged, session_patterns} ->
              [session_patterns | acc]
          end

        {:error, reason} ->
          Logger.warning(
            "跳过无效 session 文件: #{session_id}, reason=#{inspect(reason)}"
          )

          acc
      end
    end)
    |> write_global_memory_patterns()
  rescue
    exception ->
      Logger.error(
        "session memory compactor 执行失败: #{Exception.message(exception)}"
      )
  end

  defp compact_payload(
         %{"session_id" => session_id, "history" => history} = payload
       )
       when is_binary(session_id) and is_list(history) do
    protected_indexes = protected_indexes(history)

    processable_count =
      history
      |> Enum.with_index()
      |> Enum.count(fn {_msg, idx} ->
        not MapSet.member?(protected_indexes, idx)
      end)

    if processable_count < @min_compaction_messages do
      {:unchanged, session_patterns(history)}
    else
      frequency_map = message_frequencies(history, protected_indexes)

      drop_indexes =
        history
        |> Enum.with_index()
        |> Enum.reduce(MapSet.new(), fn {msg, idx}, acc ->
          if MapSet.member?(protected_indexes, idx) do
            acc
          else
            key = message_key(msg)
            freq = Map.get(frequency_map, key, 0)

            if freq <= 1 and
                 low_related?(history, idx, protected_indexes) do
              mark_related_indexes_for_drop(
                history,
                idx,
                protected_indexes,
                acc
              )
            else
              acc
            end
          end
        end)

      filtered_history =
        history
        |> Enum.with_index()
        |> Enum.reject(fn {_msg, idx} ->
          MapSet.member?(drop_indexes, idx)
        end)
        |> Enum.map(fn {msg, _idx} -> msg end)

      summary = build_session_summary(filtered_history)

      compacted_history =
        case summary do
          nil ->
            filtered_history

          summary_line ->
            upsert_summary_message(filtered_history, summary_line)
        end

      changed = compacted_history != history

      updated_payload =
        payload
        |> Map.put("history", compacted_history)
        |> Map.put(
          "updated_at",
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()
        )

      if changed do
        {:changed, updated_payload, session_patterns(compacted_history)}
      else
        {:unchanged, session_patterns(compacted_history)}
      end
    end
  end

  defp compact_payload(_payload), do: {:unchanged, %{}}

  defp protected_indexes(history) do
    history
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn {msg, idx}, acc ->
      if protected_message?(msg) do
        MapSet.put(acc, idx)
      else
        acc
      end
    end)
  end

  defp protected_message?(%{"role" => "system", "content" => content})
       when is_binary(content),
       do:
         Enum.any?(
           @protected_prefixes,
           &String.starts_with?(content, &1)
         )

  defp protected_message?(%{role: "system", content: content})
       when is_binary(content),
       do:
         Enum.any?(
           @protected_prefixes,
           &String.starts_with?(content, &1)
         )

  defp protected_message?(_), do: false

  defp message_frequencies(history, protected_indexes) do
    history
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {msg, idx}, acc ->
      if MapSet.member?(protected_indexes, idx) do
        acc
      else
        key = message_key(msg)
        Map.update(acc, key, 1, &(&1 + 1))
      end
    end)
  end

  defp message_key(msg) do
    role = normalize_role(msg)

    content =
      normalize_content(msg)
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")
      |> String.slice(0, 200)

    tool_name = Map.get(msg, "name") || Map.get(msg, :name) || ""

    {role, to_string(tool_name), content}
  end

  defp low_related?(history, idx, protected_indexes) do
    msg = Enum.at(history, idx)

    current_tokens = content_tokens(msg)

    current_tool_call_id =
      Map.get(msg, "tool_call_id") || Map.get(msg, :tool_call_id)

    neighbors =
      max(0, idx - @adjacent_window)..min(
        length(history) - 1,
        idx + @adjacent_window
      )
      |> Enum.reject(&(&1 == idx))
      |> Enum.reject(&MapSet.member?(protected_indexes, &1))
      |> Enum.map(&Enum.at(history, &1))

    related_count =
      Enum.count(neighbors, fn neighbor ->
        shared_tokens =
          MapSet.intersection(
            current_tokens,
            content_tokens(neighbor)
          )

        neighbor_tool_call_id =
          Map.get(neighbor, "tool_call_id") ||
            Map.get(neighbor, :tool_call_id)

        same_tool_call_id =
          is_binary(current_tool_call_id) and
            current_tool_call_id == neighbor_tool_call_id

        MapSet.size(shared_tokens) >= 2 or same_tool_call_id or
          request_response_pair?(msg, neighbor)
      end)

    related_count == 0
  end

  defp mark_related_indexes_for_drop(
         history,
         idx,
         protected_indexes,
         acc
       ) do
    msg = Enum.at(history, idx)

    acc = MapSet.put(acc, idx)

    max(0, idx - @adjacent_window)..min(
      length(history) - 1,
      idx + @adjacent_window
    )
    |> Enum.reject(&MapSet.member?(protected_indexes, &1))
    |> Enum.reduce(acc, fn neighbor_idx, set ->
      neighbor = Enum.at(history, neighbor_idx)

      if strong_related?(msg, neighbor) do
        MapSet.put(set, neighbor_idx)
      else
        set
      end
    end)
  end

  defp strong_related?(msg, neighbor) do
    current_tool_call_id =
      Map.get(msg, "tool_call_id") || Map.get(msg, :tool_call_id)

    neighbor_tool_call_id =
      Map.get(neighbor, "tool_call_id") ||
        Map.get(neighbor, :tool_call_id)

    same_tool_call_id =
      is_binary(current_tool_call_id) and
        current_tool_call_id == neighbor_tool_call_id

    same_tool_name =
      normalize_role(msg) == "tool" and
        normalize_role(neighbor) == "tool" and
        (Map.get(msg, "name") || Map.get(msg, :name)) ==
          (Map.get(neighbor, "name") || Map.get(neighbor, :name))

    same_tool_call_id or same_tool_name or
      request_response_pair?(msg, neighbor)
  end

  defp request_response_pair?(left, right) do
    role_pair = {normalize_role(left), normalize_role(right)}

    role_pair in [
      {"user", "assistant"},
      {"assistant", "user"},
      {"assistant", "tool"},
      {"tool", "assistant"}
    ]
  end

  defp content_tokens(msg) do
    normalize_content(msg)
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}_\s]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 3))
    |> MapSet.new()
  end

  defp build_session_summary(history) do
    role_pattern = top_role_pattern(history)
    tool_pattern = top_tool_pattern(history)
    error_fix_pattern = top_error_fix_pattern(history)

    pieces =
      [
        role_pattern && "role_flow=#{role_pattern}",
        tool_pattern && "tool_combo=#{tool_pattern}",
        error_fix_pattern && "error_fix=#{error_fix_pattern}"
      ]
      |> Enum.reject(&is_nil/1)

    if pieces == [] do
      nil
    else
      Enum.join([@summary_marker | pieces], " ")
    end
  end

  defp upsert_summary_message(history, summary_line) do
    summary_message = %{"role" => "system", "content" => summary_line}

    case Enum.find_index(history, &summary_message?/1) do
      nil -> history ++ [summary_message]
      idx -> List.replace_at(history, idx, summary_message)
    end
  end

  defp summary_message?(%{"role" => "system", "content" => content})
       when is_binary(content),
       do: String.starts_with?(content, @summary_marker)

  defp summary_message?(%{role: "system", content: content})
       when is_binary(content),
       do: String.starts_with?(content, @summary_marker)

  defp summary_message?(_), do: false

  defp top_role_pattern(history) do
    history
    |> Enum.map(&normalize_role/1)
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.map(&Enum.join(&1, "->"))
    |> most_frequent_pattern()
  end

  defp top_tool_pattern(history) do
    history
    |> Enum.filter(&(normalize_role(&1) == "tool"))
    |> Enum.map(fn msg ->
      Map.get(msg, "name") || Map.get(msg, :name) || "unknown_tool"
    end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn pair -> Enum.map_join(pair, "+", &to_string/1) end)
    |> most_frequent_pattern()
  end

  defp top_error_fix_pattern(history) do
    history
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(%{}, fn [left, right], acc ->
      if error_then_fix?(left, right) do
        key = "#{normalize_role(left)}->#{normalize_role(right)}"
        Map.update(acc, key, 1, &(&1 + 1))
      else
        acc
      end
    end)
    |> pick_pattern()
  end

  defp error_then_fix?(left, right) do
    left_content = String.downcase(normalize_content(left))
    right_content = String.downcase(normalize_content(right))

    (String.contains?(left_content, "error") or
       String.contains?(left_content, "错误")) and
      (String.contains?(right_content, "fix") or
         String.contains?(right_content, "修复") or
         String.contains?(right_content, "retry") or
         String.contains?(right_content, "重试"))
  end

  defp most_frequent_pattern(patterns) do
    patterns
    |> Enum.reduce(%{}, fn p, acc ->
      Map.update(acc, p, 1, &(&1 + 1))
    end)
    |> pick_pattern()
  end

  defp pick_pattern(freq_map) do
    case Enum.max_by(freq_map, fn {_k, v} -> v end, fn -> nil end) do
      {pattern, count} when count >= 2 -> pattern
      _ -> nil
    end
  end

  defp session_patterns(history) do
    %{
      role_pattern: top_role_pattern(history),
      tool_pattern: top_tool_pattern(history),
      error_fix_pattern: top_error_fix_pattern(history)
    }
  end

  defp write_global_memory_patterns(session_patterns_list) do
    content = build_global_memory_block(session_patterns_list)

    memory_file = Path.join(AgentPaths.config_root(), "MEMORY.md")
    File.mkdir_p!(Path.dirname(memory_file))

    existing =
      case File.read(memory_file) do
        {:ok, value} -> value
        _ -> "# MEMORY.md\n\n"
      end

    updated = upsert_managed_block(existing, content)
    _ = File.write(memory_file, updated)
  end

  defp build_global_memory_block(session_patterns_list) do
    role_patterns =
      session_patterns_list
      |> Enum.map(&Map.get(&1, :role_pattern))
      |> Enum.reject(&is_nil/1)
      |> summarize_patterns()

    tool_patterns =
      session_patterns_list
      |> Enum.map(&Map.get(&1, :tool_pattern))
      |> Enum.reject(&is_nil/1)
      |> summarize_patterns()

    error_fix_patterns =
      session_patterns_list
      |> Enum.map(&Map.get(&1, :error_fix_pattern))
      |> Enum.reject(&is_nil/1)
      |> summarize_patterns()

    lines =
      [
        "## Session Compaction Summary",
        "",
        "- 角色流模式：#{format_summary(role_patterns)}",
        "- 工具组合模式：#{format_summary(tool_patterns)}",
        "- 错误修复模式：#{format_summary(error_fix_patterns)}"
      ]

    Enum.join(lines, "\n")
  end

  defp summarize_patterns(patterns) do
    patterns
    |> Enum.reduce(%{}, fn pattern, acc ->
      Map.update(acc, pattern, 1, &(&1 + 1))
    end)
    |> Enum.sort_by(fn {_pattern, count} -> -count end)
    |> Enum.take(3)
  end

  defp format_summary([]), do: "(none)"

  defp format_summary(entries) do
    entries
    |> Enum.map(fn {pattern, count} -> "#{pattern}(#{count})" end)
    |> Enum.join(", ")
  end

  defp upsert_managed_block(existing, block_content) do
    managed =
      Enum.join([@managed_start, block_content, @managed_end], "\n")

    regex =
      Regex.compile!(
        Regex.escape(@managed_start) <>
          "[\\s\\S]*?" <> Regex.escape(@managed_end)
      )

    if Regex.match?(regex, existing) do
      Regex.replace(regex, existing, managed)
    else
      String.trim_trailing(existing) <> "\n\n" <> managed <> "\n"
    end
  end

  defp normalize_role(msg),
    do: Map.get(msg, "role") || Map.get(msg, :role) || "unknown"

  defp normalize_content(msg) do
    content = Map.get(msg, "content") || Map.get(msg, :content) || ""

    cond do
      is_binary(content) -> content
      is_map(content) or is_list(content) -> Jason.encode!(content)
      true -> to_string(content)
    end
  end
end
