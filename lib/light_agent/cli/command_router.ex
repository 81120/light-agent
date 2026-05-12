defmodule LightAgent.CLI.CommandRouter do
  @command_specs [
    %{
      cmd: "/help",
      args: "",
      group: :general,
      desc: "Show help panel",
      tips: "Start here to learn commands"
    },
    %{
      cmd: "/new",
      args: "",
      group: :session,
      desc: "Create and switch to a new session",
      tips: "A new session starts with clean context"
    },
    %{
      cmd: "/sessions",
      args: "",
      group: :session,
      desc: "List all sessions",
      tips: "Use with /switch and /resume"
    },
    %{
      cmd: "/pause",
      args: "",
      group: :session,
      desc: "Pause current session",
      tips: "No LLM calls run while paused"
    },
    %{
      cmd: "/switch",
      args: "<id>",
      group: :session,
      desc: "Switch to a session",
      tips: "Use /sessions first to find IDs"
    },
    %{
      cmd: "/resume",
      args: "<id>",
      group: :session,
      desc: "Resume a session",
      tips: "Only meaningful for paused sessions"
    },
    %{
      cmd: "/delete",
      args: "<id>",
      group: :session,
      desc: "Delete a session",
      tips: "You cannot delete the last session"
    },
    %{
      cmd: "/history",
      args: "",
      group: :view,
      desc: "Show current session history",
      tips: "Use it to quickly confirm context"
    },
    %{
      cmd: "/usage",
      args: "",
      group: :view,
      desc: "Show current token usage",
      tips: "Includes input/output/total and missing usage count"
    },
    %{
      cmd: "/skills",
      args: "",
      group: :view,
      desc: "Show registered skills",
      tips: "Displays currently enabled skill modules"
    },
    %{
      cmd: "/tools",
      args: "",
      group: :view,
      desc: "Show registered tools",
      tips: "Displays callable tools"
    },
    %{
      cmd: "/plan",
      args: "on|off|progress|apply",
      group: :session,
      desc: "Toggle/check/apply plan",
      tips: "Use plan on to draft, then apply to execute"
    },
    %{
      cmd: "/exit",
      args: "",
      group: :general,
      desc: "Exit CLI",
      tips: "You can also use Ctrl+C"
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
      "/plan on" -> {:command, :plan, :on}
      "/plan off" -> {:command, :plan, :off}
      "/plan apply" -> {:command, :plan, :apply}
      "/plan progress" -> {:command, :plan, :progress}
      "/plan" -> {:command, :plan, :progress}
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
