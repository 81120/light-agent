defmodule LightAgent.Skills.Weather do
  @moduledoc "提供天气查询和预报能力的技能包"
  use LightAgent.Core.Skill.CodeBasedSkill

  @doc "获取指定经纬度的当前天气"
  deftool(:get_weather, %{
    type: "object",
    properties: %{
      latitude: %{
        type: "number",
        description: "纬度，如 39.9042"
      },
      longitude: %{
        type: "number",
        description: "经度，如 116.4074"
      }
    },
    required: ["latitude", "longitude"]
  })

  @impl true
  def exec(:get_weather, %{"latitude" => latitude, "longitude" => longitude}) do
    res =
      Req.get!(
        "https://api.open-meteo.com/v1/forecast?latitude=#{latitude}&longitude=#{longitude}&current_weather=true",
        receive_timeout: 60000
      )

    data = res.body
    current_weather = data["current_weather"]
    current_weather_units = data["current_weather_units"]
    temperature = current_weather["temperature"]
    temperature_unit = current_weather_units["temperature"]

    "#{latitude}，#{longitude} 的天气是 #{current_weather["weathercode"]}，#{temperature} #{temperature_unit}。"
  end

  @doc "根据天气推荐合适的服装"
  deftool(:get_clothing_recommendation, %{
    type: "object",
    properties: %{
      temperature: %{
        type: "integer",
        description: "当前温度(摄氏度)，如 25"
      }
    },
    required: ["temperature"]
  })

  def exec(:get_clothing_recommendation, %{"temperature" => temperature}) do
    if temperature >= 25 do
      "建议穿短袖"
    else
      "建议穿长袖"
    end
  end
end
