defmodule LightAgent.Core.AgentPaths do
  @default_external_root "agent"
  @context_file_names ["SOUL.md", "USER.md", "MEMORY.md", "AGENT.md"]

  def external_root do
    Application.get_env(
      :light_agent,
      :agent_external_root,
      @default_external_root
    )
  end

  def skills_root do
    Path.join(external_root(), "skills")
  end

  def config_root do
    Path.join(external_root(), "config")
  end

  def context_file_paths do
    Enum.map(@context_file_names, &Path.join(config_root(), &1))
  end

  def session_memory_root do
    Path.join(external_root(), "session_memory")
  end

  def session_memory_file_path(session_id) do
    Path.join(session_memory_root(), "session-#{session_id}.md")
  end
end
