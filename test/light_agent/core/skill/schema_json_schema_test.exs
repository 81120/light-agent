defmodule LightAgent.Core.Skill.SchemaJsonSchemaTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.Skill.SchemaJsonSchema

  defmodule SimpleSchema do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:name, :string)
      field(:age, :integer)
      field(:score, :float)
      field(:active, :boolean)
    end

    def required_fields, do: [:name, :age]
  end

  defmodule ArraySchema do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:tags, {:array, :string})
      field(:numbers, {:array, :integer})
    end
  end

  defmodule NoRequiredFieldsSchema do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:optional_field, :string)
    end
  end

  describe "to_json_schema/1" do
    test "converts simple schema to JSON schema" do
      json_schema = SchemaJsonSchema.to_json_schema(SimpleSchema)

      assert json_schema.type == "object"
      assert is_map(json_schema.properties)

      assert json_schema.properties["name"] == %{type: "string"}
      assert json_schema.properties["age"] == %{type: "integer"}
      assert json_schema.properties["score"] == %{type: "number"}
      assert json_schema.properties["active"] == %{type: "boolean"}
    end

    test "includes required fields" do
      json_schema = SchemaJsonSchema.to_json_schema(SimpleSchema)

      assert "name" in json_schema.required
      assert "age" in json_schema.required
    end

    test "handles schema without required_fields function" do
      json_schema = SchemaJsonSchema.to_json_schema(NoRequiredFieldsSchema)

      assert json_schema.required == []
    end

    test "converts array types" do
      json_schema = SchemaJsonSchema.to_json_schema(ArraySchema)

      assert json_schema.properties["tags"] == %{
               type: "array",
               items: %{type: "string"}
             }

      assert json_schema.properties["numbers"] == %{
               type: "array",
               items: %{type: "integer"}
             }
    end

    test "handles unknown types as string" do
      defmodule UnknownTypeSchema do
        use Ecto.Schema

        @primary_key false
        embedded_schema do
          field(:unknown_field, :binary)
        end
      end

      json_schema = SchemaJsonSchema.to_json_schema(UnknownTypeSchema)

      assert json_schema.properties["unknown_field"] == %{type: "string"}
    end
  end

  describe "type mapping" do
    test "maps :string to string type" do
      json_schema = SchemaJsonSchema.to_json_schema(SimpleSchema)
      assert json_schema.properties["name"].type == "string"
    end

    test "maps :integer to integer type" do
      json_schema = SchemaJsonSchema.to_json_schema(SimpleSchema)
      assert json_schema.properties["age"].type == "integer"
    end

    test "maps :float to number type" do
      json_schema = SchemaJsonSchema.to_json_schema(SimpleSchema)
      assert json_schema.properties["score"].type == "number"
    end

    test "maps :boolean to boolean type" do
      json_schema = SchemaJsonSchema.to_json_schema(SimpleSchema)
      assert json_schema.properties["active"].type == "boolean"
    end
  end
end
