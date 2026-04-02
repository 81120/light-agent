defmodule LightAgent.Core.SkillTest do
  use ExUnit.Case, async: true

  defmodule EchoSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:text, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:text])
      |> validate_required([:text])
    end

    def required_fields, do: [:text]
  end

  defmodule TestSkill do
    @moduledoc "test skill"
    use LightAgent.Core.Skill.CodeBasedSkill

    @doc "Echo input text"
    deftool(:echo, schema: EchoSchema)

    @impl true
    def exec(:echo, %{"text" => text}), do: text
  end

  test "code based skill exposes definition and executes" do
    definition = TestSkill.__skill_definition__()
    [tool] = definition.tools

    assert definition.name == "TestSkill"
    assert tool.name == :echo
    assert tool.description == "Echo input text"
    assert TestSkill.echo(%{"text" => "hi"}) == "hi"
  end

  test "runner builds tool schemas" do
    tool_names =
      LightAgent.Core.Skill.Runner.build_tools_schema()
      |> Enum.map(& &1.function.name)

    assert :get_location in tool_names
    assert :get_weather in tool_names
    assert :read_file in tool_names
    assert :run_command in tool_names
  end
end

defmodule LightAgent.Skills.FilesystemTest do
  use ExUnit.Case, async: true

  test "filesystem skill reads and writes files" do
    tmp_dir = System.tmp_dir!()

    path =
      Path.join(
        tmp_dir,
        "light_agent_test_#{System.unique_integer([:positive])}.txt"
      )

    assert LightAgent.Skills.Filesystem.exec(:write_file, %{
             "path" => path,
             "content" => "abc"
           }) ==
             "成功写入文件 #{path}"

    assert LightAgent.Skills.Filesystem.exec(:read_file, %{
             "path" => path
           }) ==
             "abc"
  end
end
