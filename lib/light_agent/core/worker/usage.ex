defmodule LightAgent.Core.Worker.Usage do
  def extract_usage(response) do
    usage = Map.get(response, "usage")

    if is_map(usage) do
      prompt_tokens = to_int(Map.get(usage, "prompt_tokens"))
      completion_tokens = to_int(Map.get(usage, "completion_tokens"))

      total_tokens =
        case to_int(Map.get(usage, "total_tokens")) do
          nil ->
            if is_integer(prompt_tokens) and
                 is_integer(completion_tokens) do
              prompt_tokens + completion_tokens
            else
              nil
            end

          total ->
            total
        end

      %{
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens
      }
    else
      nil
    end
  end

  def update_token_usage(current, usage) do
    if is_map(usage) do
      %{
        prompt_tokens: current.prompt_tokens + (usage.prompt_tokens || 0),
        completion_tokens:
          current.completion_tokens + (usage.completion_tokens || 0),
        total_tokens: current.total_tokens + (usage.total_tokens || 0),
        steps: current.steps + 1,
        missing_usage_steps: current.missing_usage_steps
      }
    else
      %{
        current
        | steps: current.steps + 1,
          missing_usage_steps: current.missing_usage_steps + 1
      }
    end
  end

  def build_step_usage(usage, session_usage_total) do
    %{
      prompt_tokens: if(is_map(usage), do: usage.prompt_tokens, else: nil),
      completion_tokens:
        if(is_map(usage), do: usage.completion_tokens, else: nil),
      total_tokens: if(is_map(usage), do: usage.total_tokens, else: nil),
      session_total: session_usage_total
    }
  end

  def default_token_usage_total() do
    %{
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
      steps: 0,
      missing_usage_steps: 0
    }
  end

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_float(value), do: trunc(value)

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp to_int(_), do: nil
end
