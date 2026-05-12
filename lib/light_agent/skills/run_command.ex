defmodule LightAgent.Skills.RunCommand do
  @moduledoc "Skill package for running shell commands."

  use LightAgent.Core.Skill.CodeBasedSkill

  defmodule RunCommandParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:command, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:command])
      |> validate_required([:command])
    end

    def required_fields, do: [:command]
  end

  @doc "Run a shell command."
  deftool(:run_command, schema: RunCommandParams)

  @impl true
  def exec(:run_command, %{"command" => command}) do
    case System.cmd("sh", ["-c", command]) do
      {output, 0} ->
        output

      {output, code} ->
        "Command #{command} failed with exit code #{code}, output: #{output}"
    end
  end
end
