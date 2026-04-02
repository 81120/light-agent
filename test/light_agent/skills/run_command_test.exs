defmodule LightAgent.Skills.RunCommandTest do
  use ExUnit.Case, async: true

  alias LightAgent.Skills.RunCommand

  describe "__skill_definition__/0" do
    test "returns skill definition with correct structure" do
      definition = RunCommand.__skill_definition__()

      assert definition.name == "RunCommand"
      assert definition.description == "提供运行命令能力的技能包"
      assert is_list(definition.tools)
    end

    test "includes run_command tool" do
      definition = RunCommand.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :run_command
        end)

      assert tool != nil
      assert tool.description == "运行指定命令"
      assert tool.function == :run_command
    end

    test "run_command tool has correct param schema" do
      definition = RunCommand.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :run_command
        end)

      assert tool.param_schema == RunCommand.RunCommandParams
    end
  end

  describe "exec/2" do
    test "executes run_command with valid command" do
      result = RunCommand.exec(:run_command, %{"command" => "echo hello"})

      assert is_binary(result)
      assert String.contains?(result, "hello")
    end

    test "executes run_command with failing command" do
      result =
        RunCommand.exec(:run_command, %{
          "command" => "ls /nonexistent_directory_12345"
        })

      assert is_binary(result)
      assert String.contains?(result, "失败")
    end

    test "executes run_command with complex command" do
      result =
        RunCommand.exec(:run_command, %{"command" => "echo 'test' | wc -l"})

      assert is_binary(result)
    end
  end
end
