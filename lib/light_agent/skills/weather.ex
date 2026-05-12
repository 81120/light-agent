defmodule LightAgent.Skills.Weather do
  @moduledoc "Skill package for weather lookup and forecasting."
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

  @doc "Get current weather by coordinates."
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

        "Current weather at #{latitude}, #{longitude}: weather code #{current_weather["weathercode"]}, #{temperature} #{temperature_unit}."

      {:error, e} ->
        "Failed to get weather for #{latitude}, #{longitude}: #{inspect(e)}"
    end
  end
end
