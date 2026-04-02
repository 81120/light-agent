defmodule LightAgent.Core.Worker.SessionTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.Worker.Session

  describe "session_sort_key/1" do
    test "returns id for valid session map" do
      assert Session.session_sort_key(%{id: "session-123"}) == "session-123"
    end

    test "returns tilde for invalid input" do
      assert Session.session_sort_key(nil) == "~"
      assert Session.session_sort_key(%{}) == "~"
      assert Session.session_sort_key("invalid") == "~"
    end
  end

  describe "pick_next_session_id/1" do
    test "returns the first sorted session id" do
      sessions = %{
        "session-3" => %{status: :active},
        "session-1" => %{status: :active},
        "session-2" => %{status: :paused}
      }

      assert Session.pick_next_session_id(sessions) == "session-1"
    end

    test "returns nil for empty sessions map" do
      assert Session.pick_next_session_id(%{}) == nil
    end
  end

  describe "append_history/2" do
    test "appends item to history" do
      history = [%{role: "user", content: "hello"}]
      item = %{role: "assistant", content: "hi"}

      result = Session.append_history(history, item)

      assert result == [
               %{role: "user", content: "hello"},
               %{role: "assistant", content: "hi"}
             ]
    end

    test "appends to empty history" do
      item = %{role: "user", content: "hello"}

      result = Session.append_history([], item)

      assert result == [item]
    end
  end

  describe "append_history_list/2" do
    test "appends multiple items to history" do
      history = [%{role: "user", content: "hello"}]

      items = [
        %{role: "assistant", content: "hi"},
        %{role: "user", content: "how are you?"}
      ]

      result = Session.append_history_list(history, items)

      assert length(result) == 3
      assert result == history ++ items
    end

    test "appends empty list to history" do
      history = [%{role: "user", content: "hello"}]

      result = Session.append_history_list(history, [])

      assert result == history
    end
  end

  describe "new_session_data/0" do
    test "creates new session data with default values" do
      data = Session.new_session_data()

      assert data.status == :active
      assert is_list(data.history)
      assert is_map(data.token_usage_total)
      assert data.token_usage_total.prompt_tokens == 0
      assert data.token_usage_total.completion_tokens == 0
      assert data.token_usage_total.total_tokens == 0
    end

    test "includes system prompts in history" do
      data = Session.new_session_data()

      system_messages =
        Enum.filter(data.history, fn item ->
          item.role == "system"
        end)

      assert length(system_messages) >= 1
    end
  end
end
