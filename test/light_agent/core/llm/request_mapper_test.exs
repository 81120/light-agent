defmodule LightAgent.Core.LLM.RequestMapperTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.LLM.RequestMapper

  test "builds chat completions payload" do
    messages = [%{role: "user", content: "hello"}]
    tools = [%{type: "function", function: %{name: :read_file}}]

    body =
      RequestMapper.build_request_body(
        :chat_completions,
        "model-x",
        messages,
        tools
      )

    assert body.model == "model-x"
    assert body.messages == messages
    assert body.tools == tools
    assert body.temperature == 1
    refute Map.has_key?(body, :input)
  end

  test "builds responses payload and maps tools and messages" do
    messages = [
      %{role: "user", content: "hello"},
      %{
        role: "assistant",
        tool_calls: [
          %{
            "id" => "tool_1",
            "function" => %{
              "name" => "read_file",
              "arguments" => Jason.encode!(%{"path" => "./x"})
            }
          }
        ]
      },
      %{role: "tool", tool_call_id: "tool_1", content: "ok"}
    ]

    tools = [
      %{
        type: "function",
        function: %{
          name: :read_file,
          description: "Read file",
          parameters: %{"type" => "object"}
        }
      }
    ]

    body =
      RequestMapper.build_request_body(
        :responses,
        "model-y",
        messages,
        tools
      )

    assert body.model == "model-y"
    assert body.temperature == 1
    assert is_list(body.input)

    assert Enum.any?(body.input, fn item ->
             item["type"] == "function_call" and item["call_id"] == "tool_1"
           end)

    assert Enum.any?(body.input, fn item ->
             item["type"] == "function_call_output" and
               item["call_id"] == "tool_1" and item["output"] == "ok"
           end)

    refute Enum.any?(body.input, fn item -> item["role"] == "tool" end)

    [response_tool] = body.tools
    assert response_tool.type == "function"
    assert response_tool.name == "read_file"
    refute Map.has_key?(response_tool, :function)
  end
end
