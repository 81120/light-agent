defmodule LightAgent.Core.LLM.RequestMapper do
  def build_request_body(:chat_completions, model, messages, tools) do
    %{
      model: model,
      messages: messages,
      tools: tools,
      temperature: 1
    }
  end

  def build_request_body(:responses, model, messages, tools) do
    %{
      model: model,
      input: map_messages_for_responses(messages),
      tools: map_tools_for_responses(tools),
      temperature: 1
    }
  end

  defp map_messages_for_responses(messages) when is_list(messages) do
    messages
    |> Enum.flat_map(&map_message_for_responses/1)
  end

  defp map_messages_for_responses(_), do: []

  defp map_message_for_responses(message) when is_map(message) do
    role =
      message
      |> Map.get(:role, Map.get(message, "role"))
      |> normalize_role_for_responses()

    cond do
      role == "tool" ->
        [map_tool_output_message_for_responses(message)]

      role == "assistant" and has_tool_calls?(message) ->
        map_assistant_tool_call_messages_for_responses(message)

      true ->
        [map_standard_message_for_responses(message, role)]
    end
  end

  defp map_message_for_responses(_), do: [%{"role" => "user", "content" => ""}]

  defp map_standard_message_for_responses(message, role) do
    %{
      "role" => role,
      "content" =>
        message
        |> Map.get(:content, Map.get(message, "content"))
        |> normalize_message_content_for_responses(role)
    }
  end

  defp map_tool_output_message_for_responses(message) do
    output =
      message
      |> Map.get(:content, Map.get(message, "content"))
      |> normalize_message_content_for_responses("tool")

    case Map.get(message, :tool_call_id) || Map.get(message, "tool_call_id") do
      call_id when is_binary(call_id) and call_id != "" ->
        %{
          "type" => "function_call_output",
          "call_id" => call_id,
          "output" => output
        }

      _ ->
        %{"role" => "user", "content" => output}
    end
  end

  defp map_assistant_tool_call_messages_for_responses(message) do
    content =
      message
      |> Map.get(:content, Map.get(message, "content"))
      |> normalize_message_content_for_responses("assistant")

    tool_calls =
      Map.get(message, :tool_calls) || Map.get(message, "tool_calls") || []

    content_items =
      if content == "" do
        []
      else
        [%{"role" => "assistant", "content" => content}]
      end

    call_items =
      tool_calls
      |> Enum.map(&map_assistant_tool_call_item_for_responses/1)
      |> Enum.reject(&is_nil/1)

    case content_items ++ call_items do
      [] -> [%{"role" => "assistant", "content" => ""}]
      items -> items
    end
  end

  defp map_assistant_tool_call_item_for_responses(call) when is_map(call) do
    function_name = get_in(call, ["function", "name"])

    arguments =
      get_in(call, ["function", "arguments"])
      |> normalize_tool_arguments()

    call_id = Map.get(call, "id") || Map.get(call, "call_id")

    if is_binary(function_name) and function_name != "" and is_binary(call_id) and
         call_id != "" do
      %{
        "type" => "function_call",
        "call_id" => call_id,
        "name" => function_name,
        "arguments" => arguments
      }
    else
      nil
    end
  end

  defp map_assistant_tool_call_item_for_responses(_), do: nil

  defp has_tool_calls?(message) do
    tool_calls = Map.get(message, :tool_calls) || Map.get(message, "tool_calls")
    is_list(tool_calls) and tool_calls != []
  end

  defp normalize_role_for_responses(role) when is_atom(role),
    do: role |> Atom.to_string() |> normalize_role_for_responses()

  defp normalize_role_for_responses(role)
       when role in ["assistant", "system", "developer", "user", "tool"],
       do: role

  defp normalize_role_for_responses(_), do: "user"

  defp normalize_message_content_for_responses(content, _role)
       when is_binary(content),
       do: content

  defp normalize_message_content_for_responses(nil, _role), do: ""

  defp normalize_message_content_for_responses(content, _role)
       when is_map(content) or is_list(content) do
    case Jason.encode(content) do
      {:ok, encoded} -> encoded
      _ -> ""
    end
  end

  defp normalize_message_content_for_responses(content, _role),
    do: to_string(content)

  defp normalize_tool_arguments(arguments) when is_binary(arguments),
    do: arguments

  defp normalize_tool_arguments(arguments)
       when is_map(arguments) or is_list(arguments) do
    case Jason.encode(arguments) do
      {:ok, encoded} -> encoded
      _ -> "{}"
    end
  end

  defp normalize_tool_arguments(nil), do: "{}"
  defp normalize_tool_arguments(arguments), do: to_string(arguments)

  defp map_tools_for_responses(tools) when is_list(tools) do
    Enum.map(tools, fn tool ->
      case tool do
        %{
          type: "function",
          function: %{
            name: name,
            description: description,
            parameters: parameters
          }
        } ->
          %{
            type: "function",
            name: to_string(name),
            description: description,
            parameters: parameters
          }

        _ ->
          tool
      end
    end)
  end

  defp map_tools_for_responses(_), do: []
end
