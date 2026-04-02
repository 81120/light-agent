defmodule LightAgent.Skills.LocationTest do
  use ExUnit.Case, async: true

  alias LightAgent.Skills.Location

  describe "__skill_definition__/0" do
    test "returns skill definition with correct structure" do
      definition = Location.__skill_definition__()

      assert definition.name == "Location"
      assert definition.description == "提供位置查询能力的技能包"
      assert is_list(definition.tools)
    end

    test "includes get_location tool" do
      definition = Location.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :get_location
        end)

      assert tool != nil
      assert tool.description == "获取指定城市的经纬度"
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
               String.contains?(result, "失败")
    end
  end
end
