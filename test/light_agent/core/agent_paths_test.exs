defmodule LightAgent.Core.AgentPathsTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.AgentPaths

  describe "external_root/0" do
    test "returns default external root" do
      root = AgentPaths.external_root()
      assert root == "agent"
    end

    test "can be configured via application env" do
      original = Application.get_env(:light_agent, :agent_external_root)

      Application.put_env(:light_agent, :agent_external_root, "custom_agent")
      assert AgentPaths.external_root() == "custom_agent"

      if original do
        Application.put_env(:light_agent, :agent_external_root, original)
      else
        Application.delete_env(:light_agent, :agent_external_root)
      end
    end
  end

  describe "skills_root/0" do
    test "returns skills directory path" do
      skills_root = AgentPaths.skills_root()
      assert skills_root == Path.join(AgentPaths.external_root(), "skills")
    end
  end

  describe "config_root/0" do
    test "returns config directory path" do
      config_root = AgentPaths.config_root()
      assert config_root == Path.join(AgentPaths.external_root(), "config")
    end
  end

  describe "context_file_paths/0" do
    test "returns list of context file paths" do
      paths = AgentPaths.context_file_paths()

      assert is_list(paths)
      assert length(paths) == 4

      expected_files = ["SOUL.md", "USER.md", "MEMORY.md", "AGENT.md"]

      Enum.each(expected_files, fn file ->
        assert Enum.any?(paths, &String.ends_with?(&1, file))
      end)
    end

    test "all paths are under config root" do
      paths = AgentPaths.context_file_paths()
      config_root = AgentPaths.config_root()

      Enum.each(paths, fn path ->
        assert String.starts_with?(path, config_root)
      end)
    end
  end

  describe "session_memory_root/0" do
    test "returns session memory directory path" do
      session_root = AgentPaths.session_memory_root()

      assert session_root ==
               Path.join(AgentPaths.external_root(), "session_memory")
    end
  end

  describe "session_memory_file_path/1" do
    test "returns correct file path for session id" do
      session_id = "test-session-123"
      file_path = AgentPaths.session_memory_file_path(session_id)

      expected =
        Path.join(AgentPaths.session_memory_root(), "session-#{session_id}.md")

      assert file_path == expected
    end

    test "handles different session id formats" do
      uuid_session = "f0339ea2-0fa9-4c4a-afe2-85b740665f78"
      simple_session = "init"

      uuid_path = AgentPaths.session_memory_file_path(uuid_session)
      simple_path = AgentPaths.session_memory_file_path(simple_session)

      assert String.ends_with?(uuid_path, "session-#{uuid_session}.md")
      assert String.ends_with?(simple_path, "session-#{simple_session}.md")
    end
  end
end
