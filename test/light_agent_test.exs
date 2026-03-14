defmodule LightAgentTest do
  use ExUnit.Case
  doctest LightAgent

  test "greets the world" do
    assert LightAgent.hello() == :world
  end
end

defmodule LightAgent.Core.MemoryTest do
  use ExUnit.Case, async: false

  setup_all do
    if Process.whereis(LightAgent.Core.Memory.LongTerm) == nil do
      start_supervised!(LightAgent.Core.Memory.LongTerm)
    end

    if Process.whereis(LightAgent.Core.Memory.ShortTerm) == nil do
      start_supervised!(LightAgent.Core.Memory.ShortTerm)
    end

    :ok
  end

  setup do
    LightAgent.Core.Memory.LongTerm.reset()
    LightAgent.Core.Memory.ShortTerm.reset()
    :ok
  end

  test "long term memory appends and returns items" do
    LightAgent.Core.Memory.LongTerm.add_item(%{role: "system", content: "a"})

    LightAgent.Core.Memory.LongTerm.add_items([
      %{role: "user", content: "b"},
      %{role: "assistant", content: "c"}
    ])

    assert LightAgent.Core.Memory.LongTerm.get() == [
             %{role: "system", content: "a"},
             %{role: "user", content: "b"},
             %{role: "assistant", content: "c"}
           ]
  end

  test "short term memory keeps latest and preserves tool-call blocks" do
    LightAgent.Core.Memory.ShortTerm.add_item(%{
      role: "assistant",
      content: "a"
    })

    LightAgent.Core.Memory.ShortTerm.add_item(%{role: "tool", content: "b"})
    LightAgent.Core.Memory.ShortTerm.add_item(%{role: "user", content: "c"})

    LightAgent.Core.Memory.ShortTerm.add_item(%{
      role: "assistant",
      content: "d"
    })

    assert LightAgent.Core.Memory.ShortTerm.get() == [
             %{role: "user", content: "c"},
             %{role: "assistant", content: "d"}
           ]
  end

  test "memory all concatenates long and short" do
    LightAgent.Core.Memory.LongTerm.add_item(%{role: "system", content: "lt"})
    LightAgent.Core.Memory.ShortTerm.add_item(%{role: "user", content: "st"})

    assert LightAgent.Core.Memory.All.get() == [
             %{role: "system", content: "lt"},
             %{role: "user", content: "st"}
           ]
  end
end

defmodule LightAgent.Core.SkillTest do
  use ExUnit.Case, async: true

  defmodule TestSkill do
    @moduledoc "test skill"
    use LightAgent.Core.Skill.CodeBasedSkill

    @doc "Echo input text"
    deftool(:echo, %{
      type: "object",
      properties: %{
        text: %{type: "string"}
      },
      required: ["text"]
    })

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

    assert LightAgent.Skills.Filesystem.exec(:read_file, %{"path" => path}) ==
             "abc"
  end
end
