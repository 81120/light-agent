defmodule Mix.Tasks.LightAgent.Chat do
  use Mix.Task

  alias LightAgent.CLI.CommandRouter
  alias LightAgent.CLI.InputReader
  alias LightAgent.CLI.StatusFormatter

  @shortdoc "启动 LightAgent 交互式 CLI"

  @moduledoc """
  启动交互式 CLI。

  命令：
    /help          - 查看帮助
    /new           - 新建并切换到新 session
    /sessions      - 列出所有 session
    /pause         - 暂停当前 session
    /switch <id>   - 切换到指定 session
    /resume <id>   - 恢复指定 session
    /delete <id>   - 删除指定 session
    /history       - 查看当前 session 上下文
    /exit          - 退出

  特殊输入：
    //xxx          - 发送以 / 开头的普通文本（会被解释为 /xxx）
  """

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    case bootstrap_session() do
      {:created_new, session_id} ->
        render_welcome(session_id)

      {:restored, session_id, sessions} ->
        render_welcome(session_id)
        IO.puts(render_sessions_list(sessions))
        IO.puts(muted("检测到历史会话，未自动创建新会话。"))

      {:auto_switched, session_id, sessions} ->
        render_welcome(session_id)
        IO.puts(render_sessions_list(sessions))
        IO.puts(muted("检测到唯一历史会话，已自动切换。"))
    end

    loop_plain()
  end

  def parse_command(line), do: CommandRouter.parse(line)

  def handle_line(line) do
    case parse_command(line) do
      {:command, :help} ->
        IO.puts(render_help_panel())
        :cont

      {:command, :new} ->
        {:ok, session_id} = LightAgent.Core.Worker.new_session()
        emit_status(:success, "新会话创建成功", "session=#{session_id}")
        :cont

      {:command, :sessions} ->
        IO.puts(render_sessions())
        :cont

      {:command, :pause} ->
        {:ok, session_id} =
          LightAgent.Core.Worker.pause_current_session()

        emit_status(:warn, "当前会话已暂停", "session=#{session_id}")
        :cont

      {:command, :switch, ""} ->
        emit_status(:error, "缺少参数", "请提供 session id，例如 /switch s1")
        :cont

      {:command, :switch, session_id} ->
        case LightAgent.Core.Worker.switch_session(session_id) do
          :ok ->
            emit_status(:success, "会话切换成功", "session=#{session_id}")

          {:error, :session_not_found} ->
            emit_status(:error, "会话不存在", "session=#{session_id}")
        end

        :cont

      {:command, :resume, ""} ->
        emit_status(:error, "缺少参数", "请提供 session id，例如 /resume s1")
        :cont

      {:command, :resume, session_id} ->
        case LightAgent.Core.Worker.resume_session(session_id) do
          :ok ->
            emit_status(:success, "会话恢复成功", "session=#{session_id}")

          {:error, :session_not_found} ->
            emit_status(:error, "会话不存在", "session=#{session_id}")
        end

        :cont

      {:command, :delete, ""} ->
        emit_status(:error, "缺少参数", "请提供 session id，例如 /delete s2")
        :cont

      {:command, :delete, session_id} ->
        case LightAgent.Core.Worker.delete_session(session_id) do
          {:ok, current_session_id} ->
            emit_status(
              :success,
              "会话删除成功",
              "deleted=#{session_id}, current=#{current_session_id}"
            )

          {:error, :session_not_found} ->
            emit_status(:error, "会话不存在", "session=#{session_id}")

          {:error, :cannot_delete_last_session} ->
            emit_status(:error, "删除失败", "无法删除最后一个 session")
        end

        :cont

      {:command, :history} ->
        IO.puts(render_history())
        :cont

      {:command, :usage} ->
        IO.puts(render_usage())
        :cont

      {:command, :skills} ->
        IO.puts(render_skills())
        :cont

      {:command, :tools} ->
        IO.puts(render_tools())
        :cont

      {:command, :plan, :on} ->
        :ok = LightAgent.Core.Worker.set_mode(:plan)
        emit_status(:warn, "已进入 plan mode", "当前模式=plan（工具执行将被阻断）")
        :cont

      {:command, :plan, :off} ->
        :ok = LightAgent.Core.Worker.set_mode(:normal)
        emit_status(:success, "已退出 plan mode", "当前模式=normal")
        :cont

      {:command, :plan, :show} ->
        IO.puts(render_plan())
        :cont

      {:command, :plan, :create} ->
        mode = LightAgent.Core.Worker.current_mode()

        if mode != :plan do
          emit_status(:error, "请先进入 plan mode", "先执行 /plan on")
        else
          reply = run_agent_with_usage(plan_create_prompt())

          case upsert_plan_from_reply(reply) do
            :ok ->
              emit_status(:success, "计划草案已生成", "可用 /plan show 查看完整内容")
              IO.puts(render_plan())

            :error ->
              retry_reply = run_agent_with_usage(plan_retry_prompt())

              case upsert_plan_from_reply(retry_reply) do
                :ok ->
                  emit_status(:success, "计划草案已生成", "可用 /plan show 查看完整内容")
                  IO.puts(render_plan())

                :error ->
                  emit_status(:error, "计划解析失败", "请重试 /plan create")
                  IO.puts(format_content(retry_reply))
              end
          end
        end

        :cont

      {:command, :plan, :edit, ""} ->
        emit_status(:error, "缺少参数", "用法: /plan edit <修改要求>")
        :cont

      {:command, :plan, :edit, edit_text} ->
        mode = LightAgent.Core.Worker.current_mode()

        if mode != :plan do
          emit_status(:error, "请先进入 plan mode", "先执行 /plan on")
        else
          reply = run_agent_with_usage(plan_edit_prompt(edit_text))

          case upsert_plan_from_reply(reply) do
            :ok ->
              emit_status(:success, "计划草案已更新", "可用 /plan show 查看完整内容")
              IO.puts(render_plan())

            :error ->
              retry_reply = run_agent_with_usage(plan_retry_prompt())

              case upsert_plan_from_reply(retry_reply) do
                :ok ->
                  emit_status(:success, "计划草案已更新", "可用 /plan show 查看完整内容")
                  IO.puts(render_plan())

                :error ->
                  emit_status(:error, "计划解析失败", "请重试 /plan edit")
                  IO.puts(format_content(retry_reply))
              end
          end
        end

        :cont

      {:command, :plan, :apply} ->
        case LightAgent.Core.Worker.apply_plan() do
          :ok ->
            emit_status(:success, "计划开始执行", "status=applying")
            IO.puts(render_plan_progress())

            io_device = Process.group_leader()

            reply =
              run_agent_with_usage(
                "请按照当前计划自动继续执行：优先完成 in_progress 子任务，完成后推进到下一个，直到全部任务完成。"
              )

            IO.puts(
              io_device,
              [
                primary(role_badge("assistant")),
                format_content(reply)
              ]
              |> Enum.join("\n")
            )

          {:error, :empty_plan} ->
            emit_status(:error, "没有可执行计划", "请先 /plan create")

          {:error, reason} ->
            emit_status(:error, "执行失败", inspect(reason))
        end

        :cont

      {:command, :plan, :progress} ->
        IO.puts(render_plan_progress())
        :cont

      {:command, :plan, :reset} ->
        :ok = LightAgent.Core.Worker.reset_plan()
        emit_status(:success, "已重置计划", "status=idle")
        :cont

      {:command, :exit} ->
        IO.puts(muted("Bye."))
        :halt

      {:unknown_command, cmd} ->
        IO.puts(render_unknown_command(cmd))
        :cont

      :empty ->
        :cont

      {:message, content} ->
        io_device = Process.group_leader()
        reply = run_agent_with_usage(content)

        IO.puts(
          io_device,
          [
            primary(role_badge("assistant")),
            format_content(reply)
          ]
          |> Enum.join("\n")
        )

        :cont
    end
  end

  defp loop_plain() do
    prompt = render_prompt()

    case InputReader.read_line(prompt) do
      nil ->
        :ok

      line ->
        case handle_line(line) do
          :cont -> loop_plain()
          :halt -> :ok
        end
    end
  end

  defp emit_status(kind, title, detail) do
    status = StatusFormatter.format_status(kind, title, detail)

    IO.puts(render_status_block(status.kind, status.title, status.detail))
  end

  defp render_prompt() do
    %{
      id: id,
      status: status,
      mode: mode,
      plan_status: plan_status,
      message_count: count
    } =
      current_session_info()

    header =
      [
        muted("[LightAgent]"),
        primary("session=" <> id),
        if(status == :paused,
          do: warn("status=paused"),
          else: success("status=active")
        ),
        if(mode == :plan, do: warn("mode=plan"), else: muted("mode=normal")),
        muted("plan=#{plan_status}"),
        muted("msgs=#{count}"),
        muted("hint:/help")
      ]
      |> Enum.join(" ")

    header <> "\n" <> primary("❯ ")
  end

  def render_help_panel() do
    lines =
      CommandRouter.command_specs()
      |> Enum.map(fn spec ->
        usage = CommandRouter.format_usage(spec)

        "#{primary(String.pad_trailing(usage, 14))} #{muted(spec.desc)}"
      end)

    [
      primary("Command Panel"),
      muted("输入 //xxx 可发送以 / 开头的普通文本"),
      "" | lines
    ]
    |> Enum.join("\n")
  end

  defp render_unknown_command(cmd) do
    suggestions = CommandRouter.suggest(cmd)

    if suggestions == [] do
      render_status_block(:error, "未知命令", "/#{cmd}；输入 /help 查看所有命令")
    else
      render_status_block(
        :error,
        "未知命令",
        "/#{cmd}；你可能想输入: #{Enum.join(suggestions, ", ")}"
      )
    end
  end

  defp render_history() do
    history = LightAgent.Core.Worker.current_history()

    if history == [] do
      muted("history> (empty)")
    else
      lines =
        history
        |> Enum.with_index(1)
        |> Enum.map(fn {msg, idx} ->
          role =
            Map.get(msg, :role) || Map.get(msg, "role") || "unknown"

          content =
            Map.get(msg, :content) || Map.get(msg, "content") || ""

          "#{idx}. #{role_badge(role)} #{format_content(content)}"
        end)

      Enum.join([primary("history>") | lines], "\n")
    end
  end

  defp render_sessions() do
    sessions = LightAgent.Core.Worker.list_sessions()

    if sessions == [] do
      muted("sessions> (empty)")
    else
      lines =
        sessions
        |> Enum.map(fn %{id: id, status: status, current: current} ->
          current_mark =
            if current, do: success("●"), else: muted("○")

          status_text =
            if status == :paused,
              do: warn("paused"),
              else: success("active")

          "#{current_mark} #{primary(id)} [#{status_text}]"
        end)

      Enum.join([primary("sessions>") | lines], "\n")
    end
  end

  defp render_usage() do
    usage = LightAgent.Core.Worker.current_token_usage()

    [
      primary("usage>"),
      "in=#{usage.prompt_tokens} out=#{usage.completion_tokens} total=#{usage.total_tokens}",
      "steps=#{usage.steps} missing_usage_steps=#{usage.missing_usage_steps}"
    ]
    |> Enum.join("\n")
  end

  defp render_skills() do
    code_skills =
      LightAgent.Core.Skill.Runner.list_skills()
      |> Enum.map(&code_skill_entry/1)

    fs_skills =
      LightAgent.Core.Skill.FsBasedSkill.list_skills()
      |> Enum.map(&Map.put(&1, :source, :fs))

    lines =
      (code_skills ++ fs_skills)
      |> dedupe_skill_entries()
      |> Enum.sort_by(&String.downcase(&1.name))
      |> Enum.with_index(1)
      |> Enum.map(fn {%{name: name, description: description}, idx} ->
        "#{idx}. #{name} - #{description}"
      end)

    Enum.join([primary("skills>") | lines], "\n")
  end

  defp render_tools() do
    tools = LightAgent.Core.Skill.Runner.build_tools_schema()

    lines =
      tools
      |> Enum.with_index(1)
      |> Enum.map(fn {tool, idx} ->
        function =
          Map.get(tool, :function) || Map.get(tool, "function") || %{}

        name =
          Map.get(function, :name) || Map.get(function, "name") ||
            "unknown"

        description =
          Map.get(function, :description) ||
            Map.get(function, "description") ||
            ""

        "#{idx}. #{name} - #{description}"
      end)

    Enum.join([primary("tools>") | lines], "\n")
  end

  defp code_skill_entry(skill_module) do
    definition = skill_module.__skill_definition__()

    %{
      name: to_string(definition.name),
      description: normalize_skill_description(definition.description),
      source: :code
    }
  end

  defp normalize_skill_description(nil), do: "No description"

  defp normalize_skill_description(description)
       when is_binary(description) do
    description
    |> String.trim()
    |> case do
      "" -> "No description"
      value -> value
    end
  end

  defp normalize_skill_description(description),
    do: inspect(description)

  defp dedupe_skill_entries(entries) do
    entries
    |> Enum.reduce(%{}, fn entry, acc ->
      key = String.downcase(entry.name)

      case Map.get(acc, key) do
        nil ->
          Map.put(acc, key, entry)

        %{source: :fs} when entry.source == :code ->
          Map.put(acc, key, entry)

        _ ->
          acc
      end
    end)
    |> Map.values()
  end

  defp render_status_block(kind, title, detail) do
    badge =
      kind
      |> StatusFormatter.status_prefix()
      |> status_badge_color(kind)

    if title == "" do
      "#{badge} #{detail}"
    else
      "#{badge} #{title} #{detail}"
    end
  end

  defp status_badge_color(prefix, :success), do: success(prefix)
  defp status_badge_color(prefix, :warn), do: warn(prefix)
  defp status_badge_color(prefix, :error), do: error_text(prefix)
  defp status_badge_color(prefix, _), do: primary(prefix)

  defp role_badge(role),
    do: role |> StatusFormatter.role_badge() |> role_color(role)

  defp role_color(badge, "assistant"), do: success(badge)
  defp role_color(badge, "user"), do: primary(badge)
  defp role_color(badge, "system"), do: warn(badge)
  defp role_color(badge, _), do: muted(badge)

  defp format_content(content),
    do: StatusFormatter.normalize_content(content)

  defp run_agent_with_usage(content) do
    do_run_agent_with_usage(content, 1)
  end

  defp do_run_agent_with_usage(content, step) do
    case LightAgent.Core.Worker.run_agent_step(content) do
      {:running, tool_results, step_usage} ->
        emit_step_usage(step, step_usage)
        emit_tool_results(tool_results, current_tool_args_map())
        emit_plan_progress_if_needed()
        do_run_agent_with_usage(nil, step + 1)

      {:done, reply, step_usage} ->
        emit_step_usage(step, step_usage)
        emit_plan_progress_if_needed()
        reply
    end
  end

  defp emit_step_usage(step, step_usage) do
    detail =
      [
        "step=#{step}",
        "in=#{display_token(step_usage.prompt_tokens)}",
        "out=#{display_token(step_usage.completion_tokens)}",
        "total=#{display_token(step_usage.total_tokens)}",
        "|",
        "session in=#{step_usage.session_total.prompt_tokens}",
        "out=#{step_usage.session_total.completion_tokens}",
        "total=#{step_usage.session_total.total_tokens}",
        "steps=#{step_usage.session_total.steps}"
      ]
      |> Enum.join(" ")

    emit_status(:success, "", detail)
  end

  defp emit_tool_results([], _tool_args_map), do: :ok

  defp emit_tool_results(tool_results, tool_args_map)
       when is_list(tool_results) do
    tool_results
    |> Enum.with_index(1)
    |> Enum.each(fn {result, idx} ->
      name =
        Map.get(result, :name) || Map.get(result, "name") ||
          "unknown_tool"

      content =
        Map.get(result, :content) || Map.get(result, "content") || ""

      args_json =
        format_tool_args_json(tool_args_map, to_string(name), idx)

      detail =
        [
          "tool##{idx}",
          to_string(name),
          "args=#{args_json}",
          format_tool_content(content)
        ]
        |> Enum.join(" ")

      emit_status(:success, "", detail)
    end)
  end

  defp format_tool_content(content) when is_binary(content) do
    content
    |> StatusFormatter.normalize_content()
  end

  defp format_tool_content(content), do: inspect(content)

  defp display_token(nil), do: "n/a"
  defp display_token(value), do: to_string(value)

  defp current_tool_args_map() do
    LightAgent.Core.Worker.current_history()
    |> Enum.reverse()
    |> Enum.find(fn msg ->
      role = Map.get(msg, :role) || Map.get(msg, "role")
      role == "assistant"
    end)
    |> case do
      nil ->
        %{}

      msg ->
        tool_calls =
          Map.get(msg, :tool_calls) || Map.get(msg, "tool_calls") ||
            []

        tool_calls
        |> Enum.group_by(
          fn call ->
            call
            |> Map.get("function", %{})
            |> Map.get("name", "unknown_tool")
          end,
          fn call ->
            call
            |> Map.get("function", %{})
            |> Map.get("arguments", "{}")
            |> normalize_tool_args_json()
          end
        )
    end
  end

  defp normalize_tool_args_json(arguments)
       when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, decoded} -> Jason.encode!(decoded)
      _ -> arguments
    end
  end

  defp normalize_tool_args_json(arguments) when is_map(arguments),
    do: Jason.encode!(arguments)

  defp normalize_tool_args_json(_), do: "{}"

  defp format_tool_args_json(tool_args_map, tool_name, idx) do
    args_list = Map.get(tool_args_map, tool_name, [])

    case Enum.at(args_list, idx - 1) do
      nil -> "{}"
      args -> args
    end
  end

  defp current_session_info() do
    sessions = LightAgent.Core.Worker.list_sessions()

    current =
      Enum.find(sessions, & &1.current) ||
        %{id: "n/a", status: :active}

    plan = LightAgent.Core.Worker.current_plan()

    %{
      id: current.id,
      status: current.status,
      mode: LightAgent.Core.Worker.current_mode(),
      plan_status: Map.get(plan, "status", "idle"),
      message_count: length(LightAgent.Core.Worker.current_history())
    }
  end

  defp render_welcome(session_id) do
    IO.puts(
      [
        primary("LightAgent TUI 已启动"),
        muted("当前 session: #{session_id}"),
        muted("输入 /help 查看命令")
      ]
      |> Enum.join(" | ")
    )
  end

  defp bootstrap_session do
    sessions = LightAgent.Core.Worker.list_sessions()

    case sessions do
      [%{id: "init"}] ->
        {:ok, session_id} = LightAgent.Core.Worker.new_session()
        {:created_new, session_id}

      _ ->
        historical_sessions = Enum.reject(sessions, &(&1.id == "init"))

        case historical_sessions do
          [%{id: session_id}] ->
            :ok = LightAgent.Core.Worker.switch_session(session_id)
            {:auto_switched, session_id, LightAgent.Core.Worker.list_sessions()}

          _ ->
            current =
              Enum.find(sessions, & &1.current) || List.first(sessions)

            {:restored, current.id, sessions}
        end
    end
  end

  defp render_sessions_list(sessions) do
    lines =
      sessions
      |> Enum.map(fn %{id: id, status: status, current: current} ->
        current_mark = if current, do: success("●"), else: muted("○")

        status_text =
          if status == :paused,
            do: warn("paused"),
            else: success("active")

        "#{current_mark} #{primary(id)} [#{status_text}]"
      end)

    Enum.join([primary("sessions>") | lines], "\n")
  end

  defp render_plan() do
    plan = LightAgent.Core.Worker.current_plan()

    title = Map.get(plan, "title") || "(untitled)"
    status = Map.get(plan, "status", "idle")
    revision = Map.get(plan, "revision", 0)

    tasks =
      plan
      |> Map.get("tasks", [])
      |> Enum.map(fn task ->
        "- [#{Map.get(task, "status", "pending")}] #{Map.get(task, "id", "T?")}: #{Map.get(task, "text", "")}"
      end)

    if tasks == [] do
      Enum.join(
        [
          primary("plan>"),
          "status=#{status} revision=#{revision}",
          "title=#{title}",
          muted("(no tasks)")
        ],
        "\n"
      )
    else
      Enum.join(
        [
          primary("plan>"),
          "status=#{status} revision=#{revision}",
          "title=#{title}" | tasks
        ],
        "\n"
      )
    end
  end

  defp render_plan_progress() do
    progress = LightAgent.Core.Worker.plan_progress()
    done = Map.get(progress, "done", 0)
    total = Map.get(progress, "total", 0)

    task_lines =
      progress
      |> Map.get("tasks", [])
      |> Enum.map(fn task ->
        "- [#{task["status"]}] #{task["id"]}: #{task["text"]}"
      end)

    Enum.join(
      [primary("plan-progress>"), "done=#{done}/#{total}" | task_lines],
      "\n"
    )
  end

  defp emit_plan_progress_if_needed() do
    mode = LightAgent.Core.Worker.current_mode()
    plan = LightAgent.Core.Worker.current_plan()

    if mode == :plan and Map.get(plan, "status") == "applying" do
      IO.puts(render_plan_progress())
    end
  end

  defp plan_create_prompt do
    "请输出完整执行计划，严格返回 JSON：{\"title\": string, \"tasks\": [{\"id\": \"T1\", \"text\": string}] }"
  end

  defp plan_edit_prompt(edit_text) do
    "请基于当前计划做修改：#{edit_text}。严格返回 JSON：{\"title\": string, \"tasks\": [{\"id\": \"T1\", \"text\": string}] }"
  end

  defp plan_retry_prompt do
    "你上一次输出未能被解析。请仅返回 JSON，格式必须是：{\"title\": string, \"tasks\": [{\"id\": \"T1\", \"text\": string}] }"
  end

  defp upsert_plan_from_reply(reply) when is_binary(reply) do
    case Jason.decode(reply) do
      {:ok, %{"title" => _title, "tasks" => tasks} = plan}
      when is_list(tasks) and tasks != [] ->
        LightAgent.Core.Worker.update_plan(plan)

      _ ->
        :error
    end
  end

  defp upsert_plan_from_reply(_), do: :error

  defp ansi_enabled?() do
    IO.ANSI.enabled?() and is_nil(System.get_env("NO_COLOR"))
  end

  defp primary(text), do: colorize(text, :cyan)
  defp success(text), do: colorize(text, :green)
  defp warn(text), do: colorize(text, :yellow)
  defp error_text(text), do: colorize(text, :red)
  defp muted(text), do: colorize(text, :light_black)

  defp colorize(text, color) do
    if ansi_enabled?() do
      [apply(IO.ANSI, color, []), text, IO.ANSI.reset()]
      |> IO.iodata_to_binary()
    else
      text
    end
  end
end
