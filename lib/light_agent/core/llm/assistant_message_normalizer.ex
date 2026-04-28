defmodule LightAgent.Core.LLM.AssistantMessageNormalizer do
  def normalize_assistant_message(response) do
    extract_chat_assistant_message(response) ||
      extract_responses_assistant_message(response)
  end

  defp extract_chat_assistant_message(response) do
    response
    |> Map.get("choices", [])
    |> List.first()
    |> case do
      %{"message" => message} when is_map(message) ->
        message

      _ ->
        nil
    end
  end

  defp extract_responses_assistant_message(response) do
    output = Map.get(response, "output", [])

    if is_list(output) do
      tool_calls = extract_responses_tool_calls(output)
      content = extract_responses_content(response, output)

      cond do
        tool_calls != [] and is_binary(content) and content != "" ->
          %{
            "role" => "assistant",
            "content" => content,
            "tool_calls" => tool_calls
          }

        tool_calls != [] ->
          %{
            "role" => "assistant",
            "tool_calls" => tool_calls
          }

        is_binary(content) and content != "" ->
          %{
            "role" => "assistant",
            "content" => content
          }

        true ->
          nil
      end
    else
      nil
    end
  end

  defp extract_responses_tool_calls(output) do
    output
    |> Enum.filter(fn item ->
      Map.get(item, "type") in ["function_call", "tool_call"]
    end)
    |> Enum.map(fn item ->
      function_name =
        Map.get(item, "name") || get_in(item, ["function", "name"])

      arguments =
        Map.get(item, "arguments") ||
          get_in(item, ["function", "arguments"])

      if is_binary(function_name) and function_name != "" do
        %{
          "id" => Map.get(item, "call_id") || Map.get(item, "id"),
          "type" => "function",
          "function" => %{
            "name" => function_name,
            "arguments" => normalize_tool_arguments(arguments)
          }
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_responses_content(response, output) do
    case Map.get(response, "output_text") do
      text when is_binary(text) and text != "" ->
        text

      _ ->
        output
        |> Enum.flat_map(fn item ->
          case Map.get(item, "type") do
            "message" -> Map.get(item, "content", [])
            "output_text" -> [item]
            _ -> []
          end
        end)
        |> Enum.map(&content_item_text/1)
        |> Enum.reject(fn text -> text in [nil, ""] end)
        |> case do
          [] -> nil
          parts -> Enum.join(parts)
        end
    end
  end

  defp content_item_text(item) when is_map(item) do
    cond do
      is_binary(Map.get(item, "text")) ->
        Map.get(item, "text")

      is_binary(get_in(item, ["text", "value"])) ->
        get_in(item, ["text", "value"])

      true ->
        nil
    end
  end

  defp content_item_text(_), do: nil

  defp normalize_tool_arguments(arguments) when is_binary(arguments),
    do: arguments

  defp normalize_tool_arguments(arguments)
       when is_map(arguments) or is_list(arguments) do
    case Jason.encode(arguments) do
      {:ok, encoded} -> encoded
      _ -> "{}"
    end
  end

  defp normalize_tool_arguments(_), do: "{}"
end
