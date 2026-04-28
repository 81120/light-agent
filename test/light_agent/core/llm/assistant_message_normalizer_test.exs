defmodule LightAgent.Core.LLM.AssistantMessageNormalizerTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.LLM.AssistantMessageNormalizer

  test "extracts assistant message from chat completions response" do
    response = %{
      "choices" => [
        %{
          "message" => %{"content" => "hello", "role" => "assistant"}
        }
      ]
    }

    assert %{"content" => "hello", "role" => "assistant"} =
             AssistantMessageNormalizer.normalize_assistant_message(response)
  end

  test "extracts tool calls from responses output" do
    response = %{
      "output" => [
        %{
          "type" => "function_call",
          "id" => "tool_1",
          "name" => "read_file",
          "arguments" => %{"path" => "./x"}
        }
      ]
    }

    message = AssistantMessageNormalizer.normalize_assistant_message(response)

    assert %{"tool_calls" => tool_calls} = message

    assert [%{"id" => "tool_1", "function" => %{"name" => "read_file"}}] =
             tool_calls

    assert get_in(hd(tool_calls), ["function", "arguments"]) ==
             "{\"path\":\"./x\"}"
  end

  test "extracts text content from responses output" do
    response = %{
      "output" => [
        %{
          "type" => "message",
          "content" => [
            %{"type" => "output_text", "text" => "responses ok"}
          ]
        }
      ]
    }

    assert %{"content" => "responses ok", "role" => "assistant"} =
             AssistantMessageNormalizer.normalize_assistant_message(response)
  end

  test "returns nil for invalid responses payload" do
    assert AssistantMessageNormalizer.normalize_assistant_message(%{
             "output" => []
           }) == nil
  end
end
