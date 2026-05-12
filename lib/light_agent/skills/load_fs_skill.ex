defmodule LightAgent.Skills.LoadFsSkill do
  use LightAgent.Core.Skill.CodeBasedSkill

  alias LightAgent.Core.AgentPaths

  defmodule LoadSkillMdParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:skill_name, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:skill_name])
      |> validate_required([:skill_name])
    end

    def required_fields, do: [:skill_name]
  end

  @doc "Load the SKILL.md content for a filesystem-based skill."
  deftool(:load_skill_md, schema: LoadSkillMdParams)

  def exec(:load_skill_md, %{"skill_name" => skill_name}) do
    with :ok <- validate_skill_name(skill_name),
         raw_path <-
           Path.join([AgentPaths.skills_root(), skill_name, "SKILL.md"]),
         {:ok, skill_path} <-
           AgentPaths.normalize_and_authorize_under_root(
             raw_path,
             AgentPaths.skills_root()
           ),
         {:ok, content} <- File.read(skill_path) do
      content
    else
      {:error, :invalid_skill_name} ->
        "Failed to read SKILL.md for skill #{skill_name}: invalid skill_name"

      {:error, :outside_allowed_roots} ->
        "Failed to read SKILL.md for skill #{skill_name}: path is outside allowed roots"

      {:error, reason} ->
        "Failed to read SKILL.md for skill #{skill_name}: #{inspect(reason)}"
    end
  end

  defp validate_skill_name(skill_name) when is_binary(skill_name) do
    if Regex.match?(~r/^[A-Za-z0-9_-]+$/, skill_name) do
      :ok
    else
      {:error, :invalid_skill_name}
    end
  end

  defp validate_skill_name(_), do: {:error, :invalid_skill_name}
end
