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

  def allowed_filesystem_roots do
    cwd = Path.expand(File.cwd!())
    external = Path.expand(external_root(), cwd)

    [cwd, external]
    |> Enum.uniq()
  end

  def normalize_and_authorize_path(path) when is_binary(path) do
    normalized = Path.expand(path)

    if Enum.any?(allowed_filesystem_roots(), &within_root?(normalized, &1)) do
      {:ok, normalized}
    else
      {:error, :outside_allowed_roots}
    end
  end

  def normalize_and_authorize_path(_), do: {:error, :invalid_path}

  def normalize_and_authorize_under_root(path, root)
      when is_binary(path) and is_binary(root) do
    normalized = Path.expand(path)
    expanded_root = Path.expand(root)

    if within_root?(normalized, expanded_root) do
      {:ok, normalized}
    else
      {:error, :outside_allowed_roots}
    end
  end

  def normalize_and_authorize_under_root(_path, _root),
    do: {:error, :invalid_path}

  defp within_root?(path, root) do
    path == root or String.starts_with?(path, root <> "/")
  end
end
