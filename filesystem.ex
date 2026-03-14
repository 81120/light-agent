defmodule Toyagent.Skills.Filesystem do
  @moduledoc "提供文件系统操作能力的技能包"

  use Toyagent.Core.Skill.CodeBasedSkill

  @doc "读取指定文件内容"
  deftool(:read_file, %{
    type: "object",
    properties: %{
      path: %{
        type: "string",
        description: "文件路径，如 /path/to/file.txt"
      }
    },
    required: ["path"]
  })

  @impl true
  def exec(:read_file, %{"path" => path}) do
    case File.read(path) do
      {:ok, content} ->
        content

      {:error, reason} ->
        "读取文件 #{path} 失败: #{inspect(reason)}"
    end
  end

  @doc "写入内容到指定文件"
  deftool(:write_file, %{
    type: "object",
    properties: %{
      path: %{
        type: "string",
        description: "文件路径，如 /path/to/file.txt"
      },
      content: %{
        type: "string",
        description: "要写入的内容"
      }
    },
    required: ["path", "content"]
  })

  @impl true
  def exec(:write_file, %{"path" => path, "content" => content}) do
    case File.write(path, content) do
      :ok ->
        "成功写入文件 #{path}"

      {:error, reason} ->
        "写入文件 #{path} 失败: #{inspect(reason)}"
    end
  end
end
