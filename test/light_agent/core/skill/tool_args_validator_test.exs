defmodule LightAgent.Core.Skill.ToolArgsValidatorTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.Skill.ToolArgsValidator

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:name, :string)
      field(:age, :integer)
      field(:email, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:name, :age, :email])
      |> validate_required([:name, :age])
      |> validate_number(:age, greater_than: 0)
      |> validate_format(:email, ~r/@/, message: "must be a valid email")
    end

    def required_fields, do: [:name, :age]
  end

  def test_tool do
    %{
      name: :test_tool,
      param_schema: TestSchema
    }
  end

  describe "validate/2" do
    test "validates valid arguments" do
      args = %{"name" => "John", "age" => 25, "email" => "john@example.com"}

      {:ok, validated} = ToolArgsValidator.validate(test_tool(), args)

      assert validated["name"] == "John"
      assert validated["age"] == 25
      assert validated["email"] == "john@example.com"
    end

    test "validates arguments without optional fields" do
      args = %{"name" => "Jane", "age" => 30}

      {:ok, validated} = ToolArgsValidator.validate(test_tool(), args)

      assert validated["name"] == "Jane"
      assert validated["age"] == 30
      assert Map.get(validated, "email") == nil
    end

    test "returns error for missing required fields" do
      args = %{"name" => "John"}

      {:error, error} = ToolArgsValidator.validate(test_tool(), args)

      assert error.type == "validation_error"
      assert error.tool == "test_tool"
      assert is_list(error.errors)

      age_error =
        Enum.find(error.errors, fn e ->
          e.field == "age"
        end)

      assert age_error != nil
    end

    test "returns error for invalid field values" do
      args = %{"name" => "John", "age" => -5}

      {:error, error} = ToolArgsValidator.validate(test_tool(), args)

      assert error.type == "validation_error"

      age_error =
        Enum.find(error.errors, fn e ->
          e.field == "age"
        end)

      assert age_error != nil
    end

    test "returns error for invalid email format" do
      args = %{"name" => "John", "age" => 25, "email" => "invalid-email"}

      {:error, error} = ToolArgsValidator.validate(test_tool(), args)

      assert error.type == "validation_error"

      email_error =
        Enum.find(error.errors, fn e ->
          e.field == "email"
        end)

      assert email_error != nil
      assert String.contains?(email_error.message, "email")
    end

    test "converts atom keys to string keys" do
      args = %{name: "John", age: 25}

      {:ok, validated} = ToolArgsValidator.validate(test_tool(), args)

      assert Map.has_key?(validated, "name")
      assert Map.has_key?(validated, "age")
    end
  end
end
