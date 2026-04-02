defmodule LightAgent.Skills.Weather do
  @moduledoc "提供天气查询和预报能力的技能包"
  use LightAgent.Core.Skill.CodeBasedSkill

  defmodule GetWeatherParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:latitude, :float)
      field(:longitude, :float)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:latitude, :longitude])
      |> validate_required([:latitude, :longitude])
    end

    def required_fields, do: [:latitude, :longitude]
  end

  defmodule GetClothingRecommendationParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:temperature, :integer)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:temperature])
      |> validate_required([:temperature])
    end

    def required_fields, do: [:temperature]
  end

  @doc "获取指定经纬度的当前天气"
  deftool(:get_weather, schema: GetWeatherParams)

  @impl true
  def exec(:get_weather, %{
        "latitude" => latitude,
        "longitude" => longitude
      }) do
    case Req.get(
           "https://api.open-meteo.com/v1/forecast?latitude=#{latitude}&longitude=#{longitude}&current_weather=true",
           receive_timeout: 300_000
         ) do
      {:ok, res} ->
        data = res.body
        current_weather = data["current_weather"]
        current_weather_units = data["current_weather_units"]
        temperature = current_weather["temperature"]
        temperature_unit = current_weather_units["temperature"]

        "#{latitude}，#{longitude} 的天气是 #{current_weather["weathercode"]}，#{temperature} #{temperature_unit}。"

      {:error, e} ->
        "获取 #{latitude}，#{longitude} 的天气失败: #{inspect(e)}"
    end
  end
end
