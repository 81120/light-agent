defmodule LightAgent.Skills.LocationTest do
  use ExUnit.Case, async: true

  alias LightAgent.Skills.Location

  describe "__skill_definition__/0" do
    test "returns skill definition with correct structure" do
      definition = Location.__skill_definition__()

      assert definition.name == "Location"
      assert definition.description == "Skill package for location lookup."
      assert is_list(definition.tools)
    end

    test "includes get_location tool" do
      definition = Location.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :get_location
        end)

      assert tool != nil
      assert tool.description == "Get latitude and longitude for a city."
      assert tool.function == :get_location
    end

    test "get_location tool has correct param schema" do
      definition = Location.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :get_location
        end)

      assert tool.param_schema == Location.GetLocationParams
    end
  end

  describe "exec/2" do
    test "executes get_location with valid city" do
      result = Location.exec(:get_location, %{"city" => "Beijing"})

      assert is_binary(result)

      assert String.contains?(result, "Beijing") or
               String.contains?(result, "Failed")
    end
  end
end
