defmodule LightAgent.Skills.FilesystemExtendedTest do
  use ExUnit.Case, async: true

  alias LightAgent.Skills.Filesystem

  describe "__skill_definition__/0" do
    test "returns skill definition with correct structure" do
      definition = Filesystem.__skill_definition__()

      assert definition.name == "Filesystem"
      assert definition.description == "提供文件系统操作能力的技能包"
      assert is_list(definition.tools)
    end

    test "includes read_file tool" do
      definition = Filesystem.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :read_file
        end)

      assert tool != nil
      assert tool.description == "读取指定文件内容"
      assert tool.function == :read_file
    end

    test "includes write_file tool" do
      definition = Filesystem.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :write_file
        end)

      assert tool != nil
      assert tool.description == "写入内容到指定文件"
      assert tool.function == :write_file
    end

    test "read_file tool has correct param schema" do
      definition = Filesystem.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :read_file
        end)

      assert tool.param_schema == Filesystem.ReadFileParams
    end

    test "write_file tool has correct param schema" do
      definition = Filesystem.__skill_definition__()

      tool =
        Enum.find(definition.tools, fn tool ->
          tool.name == :write_file
        end)

      assert tool.param_schema == Filesystem.WriteFileParams
    end
  end

  describe "exec/2" do
    test "reads non-existent file returns error" do
      result =
        Filesystem.exec(:read_file, %{
          "path" => "/nonexistent/path/to/file.txt"
        })

      assert is_binary(result)
      assert String.contains?(result, "失败")
    end

    test "writes and reads file with unicode content" do
      test_dir = Path.join(File.cwd!(), ".tmp_light_agent_tests")
      File.mkdir_p!(test_dir)

      path =
        Path.join(
          test_dir,
          "light_agent_unicode_test_#{System.unique_integer([:positive])}.txt"
        )

      unicode_content = "你好世界 🌍 Hello World"

      write_result =
        Filesystem.exec(:write_file, %{
          "path" => path,
          "content" => unicode_content
        })

      assert String.contains?(write_result, "成功")

      result = Filesystem.exec(:read_file, %{"path" => path})

      assert result == unicode_content
    end

    test "rejects writes outside allowed roots" do
      result =
        Filesystem.exec(:write_file, %{
          "path" => "/tmp/light_agent_outside_test.txt",
          "content" => "test"
        })

      assert String.contains?(result, "路径不在允许范围内")
    end

    test "normalizes relative path inside project root" do
      test_dir = Path.join(File.cwd!(), ".tmp_light_agent_tests")
      File.mkdir_p!(test_dir)

      relative_path =
        ".tmp_light_agent_tests/../.tmp_light_agent_tests/normalized_test.txt"

      write_result =
        Filesystem.exec(:write_file, %{
          "path" => relative_path,
          "content" => "ok"
        })

      expected_path =
        Path.join(test_dir, "normalized_test.txt")
        |> Path.expand()

      assert write_result == "成功写入文件 #{expected_path}"

      read_result = Filesystem.exec(:read_file, %{"path" => relative_path})
      assert read_result == "ok"
    end

    test "writes to invalid path returns error" do
      result =
        Filesystem.exec(:write_file, %{
          "path" => "/nonexistent/directory/file.txt",
          "content" => "test"
        })

      assert is_binary(result)
      assert String.contains?(result, "失败")
    end
  end
end

defmodule LightAgent.Skills.LoadFsSkillTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.AgentPaths
  alias LightAgent.Skills.LoadFsSkill

  test "loads SKILL.md from allowed root" do
    skill_name = "test_skill_#{System.unique_integer([:positive])}"
    skill_dir = Path.join(AgentPaths.skills_root(), skill_name)
    skill_md = Path.join(skill_dir, "SKILL.md")

    File.mkdir_p!(skill_dir)
    File.write!(skill_md, "# test skill")

    result = LoadFsSkill.exec(:load_skill_md, %{"skill_name" => skill_name})

    assert result == "# test skill"
  end

  test "rejects invalid skill name" do
    result = LoadFsSkill.exec(:load_skill_md, %{"skill_name" => "../escape"})

    assert String.contains?(result, "非法 skill_name")
  end
end
