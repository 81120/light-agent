defmodule ToyagentTest do
  use ExUnit.Case
  doctest Toyagent

  test "greets the world" do
    assert Toyagent.hello() == :world
  end
end

defmodule Toyagent.Core.MemoryTest do
  use ExUnit.Case, async: false

  setup_all do
    if Process.whereis(Toyagent.Core.Memory.LongTerm) == nil do
      start_supervised!(Toyagent.Core.Memory.LongTerm)
    end

    if Process.whereis(Toyagent.Core.Memory.ShortTerm) == nil do
      start_supervised!(Toyagent.Core.Memory.ShortTerm)
    end

    :ok
  end

  setup do
    Toyagent.Core.Memory.LongTerm.reset()
    Toyagent.Core.Memory.ShortTerm.reset()
    :ok
  end

  test "long term memory appends and returns items" do
    Toyagent.Core.Memory.LongTerm.add_item(%{role: "system", content: "a"})
    Toyagent.Core.Memory.LongTerm.add_items([
      %{role: "user", content: "b"},
      %{role: "assistant", content: "c"}
    ])

    assert Toyagent.Core.Memory.LongTerm.get() == [
             %{role: "system", content: "a"},
             %{role: "user", content: "b"},
             %{role: "assistant", content: "c"}
           ]
  end

  test "short term memory keeps latest and preserves tool-call blocks" do
    Toyagent.Core.Memory.ShortTerm.add_item(%{role: "assistant", content: "a"})
    Toyagent.Core.Memory.ShortTerm.add_item(%{role: "tool", content: "b"})
    Toyagent.Core.Memory.ShortTerm.add_item(%{role: "user", content: "c"})
    Toyagent.Core.Memory.ShortTerm.add_item(%{role: "assistant", content: "d"})

    assert Toyagent.Core.Memory.ShortTerm.get() == [
             %{role: "user", content: "c"},
             %{role: "assistant", content: "d"}
           ]
  end

  test "memory all concatenates long and short" do
    Toyagent.Core.Memory.LongTerm.add_item(%{role: "system", content: "lt"})
    Toyagent.Core.Memory.ShortTerm.add_item(%{role: "user", content: "st"})

    assert Toyagent.Core.Memory.All.get() == [
             %{role: "system", content: "lt"},
             %{role: "user", content: "st"}
           ]
  end
end

defmodule Toyagent.Core.SkillTest do
  use ExUnit.Case, async: true

  defmodule TestSkill do
    @moduledoc "test skill"
    use Toyagent.Core.Skill.CodeBasedSkill

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
      Toyagent.Core.Skill.Runner.build_tools_schema()
      |> Enum.map(& &1.function.name)

    assert :get_location in tool_names
    assert :get_weather in tool_names
    assert :read_file in tool_names
    assert :run_command in tool_names
  end
end

defmodule Toyagent.Skills.FilesystemTest do
  use ExUnit.Case, async: true

  test "filesystem skill reads and writes files" do
    tmp_dir = System.tmp_dir!()
    path = Path.join(tmp_dir, "toyagent_test_#{System.unique_integer([:positive])}.txt")

    assert Toyagent.Skills.Filesystem.exec(:write_file, %{"path" => path, "content" => "abc"}) ==
             "成功写入文件 #{path}"

    assert Toyagent.Skills.Filesystem.exec(:read_file, %{"path" => path}) == "abc"
  end
end
