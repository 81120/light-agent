defmodule LightAgent.Skills.Location do
  @moduledoc "提供位置查询能力的技能包"

  use LightAgent.Core.Skill.CodeBasedSkill

  @doc "获取指定城市的经纬度"
  deftool(:get_location, %{
    type: "object",
    properties: %{
      city: %{
        type: "string",
        description: "城市名称，如 Beijing"
      }
    },
    required: ["city"]
  })

  @impl true
  def exec(:get_location, %{"city" => city}) do
    res =
      Req.get!(
        "https://geocoding-api.open-meteo.com/v1/search",
        params: [name: city],
        receive_timeout: 60_000
      )

    data = res.body["results"] |> List.first()
    latitude = data["latitude"]
    longitude = data["longitude"]

    "#{city} 的经纬度是 #{Jason.encode!(%{"latitude" => latitude, "longitude" => longitude})}。"
  end
end
