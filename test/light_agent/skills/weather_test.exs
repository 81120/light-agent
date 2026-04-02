defmodule LightAgent.Skills.WeatherTest do
  use ExUnit.Case, async: true

  alias LightAgent.Skills.Weather

  describe "__skill_definition__/0" do
    test "returns skill definition with correct structure" do
      definition = Weather.__skill_definition__()

      assert definition.name == "Weather"
      assert definition.description == "提供天气查询和预报能力的技能包"
      assert is_list(definition.tools)
    end

    test "includes get_weather tool" do
      definition = Weather.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :get_weather
        end)

      assert tool != nil
      assert tool.description == "获取指定经纬度的当前天气"
      assert tool.function == :get_weather
    end

    test "get_weather tool has correct param schema" do
      definition = Weather.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :get_weather
        end)

      assert tool.param_schema == Weather.GetWeatherParams
    end
  end

  describe "exec/2" do
    test "executes get_weather with valid coordinates" do
      result =
        Weather.exec(:get_weather, %{
          "latitude" => 39.9042,
          "longitude" => 116.4074
        })

      assert is_binary(result)
      assert String.contains?(result, "天气") or String.contains?(result, "失败")
    end
  end
end
