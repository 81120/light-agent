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

defmodule LightAgent.Core.Skill.RunnerSecurityTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias LightAgent.Core.Skill.Runner

  test "run_command requires confirmation and can be denied" do
    result =
      capture_io("n\n", fn ->
        [result] =
          Runner.handle_tool_call([
            %{
              "id" => "tool_1",
              "function" => %{
                "name" => "run_command",
                "arguments" => Jason.encode!(%{"command" => "echo hello"})
              }
            }
          ])

        send(self(), {:runner_result, result})
      end)

    assert is_binary(result)
    assert_receive {:runner_result, runner_result}
    assert runner_result.name == "run_command"

    {:ok, payload} = Jason.decode(runner_result.content)
    assert payload["type"] == "permission_denied"
    assert payload["tool"] == "run_command"
  end

  test "run_command requires confirmation and can be allowed" do
    _output =
      capture_io("y\n", fn ->
        [result] =
          Runner.handle_tool_call([
            %{
              "id" => "tool_2",
              "function" => %{
                "name" => "run_command",
                "arguments" => Jason.encode!(%{"command" => "echo hello"})
              }
            }
          ])

        send(self(), {:runner_result, result})
      end)

    assert_receive {:runner_result, result}
    assert result.name == "run_command"
    assert String.contains?(result.content, "hello")
  end

  test "read_file does not require confirmation" do
    tmp_dir = System.tmp_dir!()

    path =
      Path.join(
        tmp_dir,
        "light_agent_read_runner_#{System.unique_integer([:positive])}.txt"
      )

    :ok = File.write(path, "abc")

    [result] =
      Runner.handle_tool_call([
        %{
          "id" => "tool_3",
          "function" => %{
            "name" => "read_file",
            "arguments" => Jason.encode!(%{"path" => path})
          }
        }
      ])

    assert result.name == "read_file"
    assert result.content == "abc"
  end

  test "plan mode blocks tool execution" do
    [result] =
      Runner.handle_tool_call(
        [
          %{
            "id" => "tool_4",
            "function" => %{
              "name" => "run_command",
              "arguments" => Jason.encode!(%{"command" => "echo hello"})
            }
          }
        ],
        mode: :plan,
        plan_phase: :draft
      )

    assert result.name == "run_command"

    {:ok, payload} = Jason.decode(result.content)
    assert payload["type"] == "plan_mode_blocked"
    assert payload["tool"] == "run_command"
  end
end

defmodule LightAgent.CLI.CommandRouterPlanTest do
  use ExUnit.Case, async: true

  alias LightAgent.CLI.CommandRouter

  test "parses plan commands" do
    assert CommandRouter.parse("/plan on") == {:command, :plan, :on}
    assert CommandRouter.parse("/plan off") == {:command, :plan, :off}
    assert CommandRouter.parse("/plan show") == {:command, :plan, :show}
    assert CommandRouter.parse("/plan create") == {:command, :plan, :create}
    assert CommandRouter.parse("/plan apply") == {:command, :plan, :apply}
    assert CommandRouter.parse("/plan progress") == {:command, :plan, :progress}
    assert CommandRouter.parse("/plan reset") == {:command, :plan, :reset}

    assert CommandRouter.parse("/plan edit add tests") ==
             {:command, :plan, :edit, "add tests"}

    assert CommandRouter.parse("/plan edit") == {:command, :plan, :edit, ""}
    assert CommandRouter.parse("/plan") == {:command, :plan, :show}
  end
end

defmodule LightAgent.Core.SessionServerPlanStateTest do
  use ExUnit.Case, async: false

  alias LightAgent.Core.SessionServer

  test "updates plan, apply starts first task, and progress reports totals" do
    session_id = "plan-test-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    :ok =
      GenServer.call(
        SessionServer.via_tuple(session_id),
        {:update_plan,
         %{
           "title" => "demo",
           "tasks" => [
             %{"text" => "step 1"},
             %{"id" => "T2", "text" => "step 2"}
           ]
         }}
      )

    plan = GenServer.call(SessionServer.via_tuple(session_id), :current_plan)
    assert plan["status"] == "idle"
    assert plan["revision"] == 1
    assert Enum.map(plan["tasks"], & &1["id"]) == ["T1", "T2"]
    assert Enum.map(plan["tasks"], & &1["status"]) == ["pending", "pending"]

    assert :ok =
             GenServer.call(SessionServer.via_tuple(session_id), :apply_plan)

    progress =
      GenServer.call(SessionServer.via_tuple(session_id), :plan_progress)

    assert progress["done"] == 0
    assert progress["total"] == 2
    assert hd(progress["tasks"])["status"] == "in_progress"

    GenServer.stop(pid)
  end

  test "apply_plan rejects empty plan" do
    session_id = "plan-empty-#{System.unique_integer([:positive])}"
    {:ok, pid} = SessionServer.start_link(session_id: session_id, history: [])

    assert {:error, :empty_plan} =
             GenServer.call(SessionServer.via_tuple(session_id), :apply_plan)

    GenServer.stop(pid)
  end
end
