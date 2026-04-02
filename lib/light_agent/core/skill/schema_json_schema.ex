defmodule LightAgent.Core.Skill.SchemaJsonSchema do
  def to_json_schema(schema_module) do
    fields = schema_module.__schema__(:fields)

    properties =
      fields
      |> Enum.reduce(%{}, fn field, acc ->
        type = schema_module.__schema__(:type, field)
        Map.put(acc, Atom.to_string(field), type_to_json_schema(type))
      end)

    %{
      type: "object",
      properties: properties,
      required: required_fields(schema_module)
    }
  end

  defp required_fields(schema_module) do
    if function_exported?(schema_module, :required_fields, 0) do
      schema_module.required_fields()
      |> Enum.map(&to_string/1)
    else
      []
    end
  end

  defp type_to_json_schema(:string), do: %{type: "string"}
  defp type_to_json_schema(:integer), do: %{type: "integer"}
  defp type_to_json_schema(:float), do: %{type: "number"}
  defp type_to_json_schema(:decimal), do: %{type: "number"}
  defp type_to_json_schema(:boolean), do: %{type: "boolean"}

  defp type_to_json_schema({:array, item_type}) do
    %{
      type: "array",
      items: type_to_json_schema(item_type)
    }
  end

  defp type_to_json_schema(_), do: %{type: "string"}
end
