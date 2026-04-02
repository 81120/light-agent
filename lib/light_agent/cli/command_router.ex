defmodule LightAgent.CLI.CommandRouter do
  @command_specs [
    %{
      cmd: "/help",
      args: "",
      group: :general,
      desc: "显示帮助面板",
      tips: "先用它了解命令"
    },
    %{
      cmd: "/new",
      args: "",
      group: :session,
      desc: "创建并切换到新会话",
      tips: "新会话从干净上下文开始"
    },
    %{
      cmd: "/sessions",
      args: "",
      group: :session,
      desc: "列出所有会话",
      tips: "配合 /switch 和 /resume 使用"
    },
    %{
      cmd: "/pause",
      args: "",
      group: :session,
      desc: "暂停当前会话",
      tips: "暂停后不会执行 LLM 调用"
    },
    %{
      cmd: "/switch",
      args: "<id>",
      group: :session,
      desc: "切换到指定会话",
      tips: "先用 /sessions 查看 id"
    },
    %{
      cmd: "/resume",
      args: "<id>",
      group: :session,
      desc: "恢复指定会话",
      tips: "仅对 paused 会话有意义"
    },
    %{
      cmd: "/delete",
      args: "<id>",
      group: :session,
      desc: "删除指定会话",
      tips: "不能删除最后一个会话"
    },
    %{
      cmd: "/history",
      args: "",
      group: :view,
      desc: "查看当前会话历史",
      tips: "用于快速确认上下文"
    },
    %{
      cmd: "/usage",
      args: "",
      group: :view,
      desc: "查看当前会话 token 使用",
      tips: "显示输入/输出/总量与缺失统计"
    },
    %{
      cmd: "/skills",
      args: "",
      group: :view,
      desc: "查看已注册 skill",
      tips: "显示当前启用的 skill 模块"
    },
    %{
      cmd: "/tools",
      args: "",
      group: :view,
      desc: "查看已注册 tool",
      tips: "显示当前可调用工具"
    },
    %{
      cmd: "/exit",
      args: "",
      group: :general,
      desc: "退出 CLI",
      tips: "也可以使用 Ctrl+C"
    }
  ]

  @commands Enum.map(@command_specs, & &1.cmd)

  def command_specs, do: @command_specs

  def commands, do: @commands

  def format_usage(%{cmd: cmd, args: ""}), do: cmd
  def format_usage(%{cmd: cmd, args: args}), do: "#{cmd} #{args}"

  def parse(line) do
    case String.trim(line) do
      "//" -> {:message, "/"}
      "//" <> content -> {:message, "/" <> content}
      "/help" -> {:command, :help}
      "/new" -> {:command, :new}
      "/sessions" -> {:command, :sessions}
      "/pause" -> {:command, :pause}
      "/history" -> {:command, :history}
      "/usage" -> {:command, :usage}
      "/skills" -> {:command, :skills}
      "/tools" -> {:command, :tools}
      "/exit" -> {:command, :exit}
      "/switch " <> id -> {:command, :switch, String.trim(id)}
      "/resume " <> id -> {:command, :resume, String.trim(id)}
      "/delete " <> id -> {:command, :delete, String.trim(id)}
      "/" <> cmd -> {:unknown_command, cmd}
      "" -> :empty
      content -> {:message, content}
    end
  end

  def suggest(cmd) do
    normalized = "/" <> cmd

    @commands
    |> Enum.filter(fn known ->
      String.starts_with?(known, normalized)
    end)
    |> Enum.take(3)
  end
end
