defmodule LightAgent.Core.Skill.ToolArgsValidator do
  def validate(tool, args) do
    tool
    |> Map.fetch!(:param_schema)
    |> validate_with_schema(tool, args)
  end

  defp validate_with_schema(param_schema, tool, args) do
    changeset = param_schema.changeset(args)

    if changeset.valid? do
      {:ok,
       changeset
       |> Ecto.Changeset.apply_changes()
       |> Map.from_struct()
       |> stringify_keys()}
    else
      {:error,
       %{
         type: "validation_error",
         tool: tool_name(tool),
         errors: format_errors(changeset)
       }}
    end
  end

  defp tool_name(tool), do: tool[:name] |> to_string()

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} ->
      %{field: to_string(field), message: Enum.join(messages, ", ")}
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {to_string(key), stringify_value(value)}
    end)
    |> Map.new()
  end

  defp stringify_value(value) when is_map(value),
    do: stringify_keys(value)

  defp stringify_value(value) when is_list(value),
    do: Enum.map(value, &stringify_value/1)

  defp stringify_value(value), do: value
end
