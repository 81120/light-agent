defmodule LightAgent.Core.SessionMemoryStoreTest do
  use ExUnit.Case, async: false

  alias LightAgent.Core.SessionMemoryStore
  alias LightAgent.Core.AgentPaths

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "light_agent_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    original_root = Application.get_env(:light_agent, :agent_external_root)
    Application.put_env(:light_agent, :agent_external_root, tmp_dir)

    on_exit(fn ->
      if original_root do
        Application.put_env(:light_agent, :agent_external_root, original_root)
      else
        Application.delete_env(:light_agent, :agent_external_root)
      end

      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "list_session_ids/0" do
    test "returns empty list when no sessions exist" do
      assert SessionMemoryStore.list_session_ids() == []
    end

    test "returns list of session ids" do
      session_id = "test-session-123"
      history = [%{role: "user", content: "hello"}]

      :ok = SessionMemoryStore.persist_session(session_id, history)

      ids = SessionMemoryStore.list_session_ids()
      assert session_id in ids
    end
  end

  describe "persist_session/2 and load_session/1" do
    test "persists and loads session history" do
      session_id = "test-session-456"

      history = [
        %{"role" => "system", "content" => "You are a helpful assistant"},
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"}
      ]

      :ok = SessionMemoryStore.persist_session(session_id, history)

      {:ok, loaded_history} = SessionMemoryStore.load_session(session_id)

      assert length(loaded_history) == 3
      assert hd(loaded_history)["role"] == "system"
    end

    test "returns error for non-existent session" do
      assert {:error, :enoent} = SessionMemoryStore.load_session("non-existent")
    end
  end

  describe "load_session_payload/1" do
    test "loads full session payload" do
      session_id = "test-session-789"
      history = [%{role: "user", content: "test"}]

      :ok = SessionMemoryStore.persist_session(session_id, history)

      {:ok, payload} = SessionMemoryStore.load_session_payload(session_id)

      assert payload["session_id"] == session_id
      assert is_list(payload["history"])
      assert payload["updated_at"]
    end
  end

  describe "persist_session_payload/1" do
    test "persists valid payload" do
      payload = %{
        "session_id" => "test-payload-123",
        "history" => [%{role: "user", content: "test"}]
      }

      :ok = SessionMemoryStore.persist_session_payload(payload)

      {:ok, loaded} =
        SessionMemoryStore.load_session_payload("test-payload-123")

      assert loaded["session_id"] == "test-payload-123"
    end

    test "adds updated_at if not provided" do
      payload = %{
        "session_id" => "test-payload-456",
        "history" => []
      }

      :ok = SessionMemoryStore.persist_session_payload(payload)

      {:ok, loaded} =
        SessionMemoryStore.load_session_payload("test-payload-456")

      assert loaded["updated_at"]
    end

    test "skips rewrite when only updated_at changes" do
      session_id = "test-stable-write-123"
      file_path = AgentPaths.session_memory_file_path(session_id)

      payload_v1 = %{
        "session_id" => session_id,
        "updated_at" => "2026-01-01T00:00:00Z",
        "history" => [%{role: "assistant", content: "hello"}]
      }

      payload_v2 = %{
        "session_id" => session_id,
        "updated_at" => "2026-02-01T00:00:00Z",
        "history" => [%{role: "assistant", content: "hello"}]
      }

      :ok = SessionMemoryStore.persist_session_payload(payload_v1)
      {:ok, first_write} = File.read(file_path)

      :ok = SessionMemoryStore.persist_session_payload(payload_v2)
      {:ok, second_write} = File.read(file_path)

      assert first_write == second_write
    end

    test "rewrites file when payload content changes" do
      session_id = "test-rewrite-when-changed-123"
      file_path = AgentPaths.session_memory_file_path(session_id)

      payload_v1 = %{
        "session_id" => session_id,
        "updated_at" => "2026-01-01T00:00:00Z",
        "history" => [%{role: "assistant", content: "hello"}]
      }

      payload_v2 = %{
        "session_id" => session_id,
        "updated_at" => "2026-02-01T00:00:00Z",
        "history" => [%{role: "assistant", content: "hello world"}]
      }

      :ok = SessionMemoryStore.persist_session_payload(payload_v1)
      {:ok, first_write} = File.read(file_path)

      :ok = SessionMemoryStore.persist_session_payload(payload_v2)
      {:ok, second_write} = File.read(file_path)

      refute first_write == second_write
    end

    test "returns error for invalid payload" do
      assert {:error, :invalid_payload} =
               SessionMemoryStore.persist_session_payload(%{})

      assert {:error, :invalid_payload} =
               SessionMemoryStore.persist_session_payload(nil)
    end
  end

  describe "delete_session/1" do
    test "deletes existing session" do
      session_id = "test-delete-123"
      history = [%{role: "user", content: "test"}]

      :ok = SessionMemoryStore.persist_session(session_id, history)
      :ok = SessionMemoryStore.delete_session(session_id)

      assert {:error, :enoent} = SessionMemoryStore.load_session(session_id)
    end

    test "returns ok for non-existent session" do
      assert :ok = SessionMemoryStore.delete_session("non-existent")
    end
  end

  describe "file format" do
    test "creates markdown file with json block" do
      session_id = "test-format-123"
      history = [%{role: "user", content: "test"}]

      :ok = SessionMemoryStore.persist_session(session_id, history)

      file_path = AgentPaths.session_memory_file_path(session_id)
      {:ok, content} = File.read(file_path)

      assert String.starts_with?(content, "# Session ")
      assert String.contains?(content, "```json")
      assert String.contains?(content, "```")
    end
  end
end
