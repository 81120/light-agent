defmodule LightAgent.Skills.Location do
  @moduledoc "提供位置查询能力的技能包"

  use LightAgent.Core.Skill.CodeBasedSkill

  defmodule GetLocationParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:city, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:city])
      |> validate_required([:city])
    end

    def required_fields, do: [:city]
  end

  @doc "获取指定城市的经纬度"
  deftool(:get_location, schema: GetLocationParams)

  @impl true
  def exec(:get_location, %{"city" => city}) do
    case Req.get(
           "https://geocoding-api.open-meteo.com/v1/search",
           params: [name: city],
           receive_timeout: 300_000
         ) do
      {:ok, res} ->
        data = res.body["results"] |> List.first()
        latitude = data["latitude"]
        longitude = data["longitude"]

        "#{city} 的经纬度是 #{Jason.encode!(%{"latitude" => latitude, "longitude" => longitude})}。"

      {:error, e} ->
        "获取 #{city} 的经纬度失败: #{inspect(e)}"
    end
  end
end
