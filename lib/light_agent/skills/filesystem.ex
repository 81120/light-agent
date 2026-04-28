defmodule LightAgent.Skills.Filesystem do
  @moduledoc "提供文件系统操作能力的技能包"

  use LightAgent.Core.Skill.CodeBasedSkill

  alias LightAgent.Core.AgentPaths

  defmodule ReadFileParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:path, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:path])
      |> validate_required([:path])
    end

    def required_fields, do: [:path]
  end

  defmodule WriteFileParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:path, :string)
      field(:content, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:path, :content])
      |> validate_required([:path, :content])
    end

    def required_fields, do: [:path, :content]
  end

  @doc "读取指定文件内容"
  deftool(:read_file, schema: ReadFileParams)

  @impl true
  def exec(:read_file, %{"path" => path}) do
    with {:ok, normalized_path} <- AgentPaths.normalize_and_authorize_path(path),
         {:ok, content} <- File.read(normalized_path) do
      content
    else
      {:error, :outside_allowed_roots} ->
        "读取文件 #{path} 失败: 路径不在允许范围内"

      {:error, reason} ->
        "读取文件 #{path} 失败: #{inspect(reason)}"
    end
  end

  @doc "写入内容到指定文件"
  deftool(:write_file, schema: WriteFileParams)

  @impl true
  def exec(:write_file, %{"path" => path, "content" => content}) do
    with {:ok, normalized_path} <- AgentPaths.normalize_and_authorize_path(path),
         :ok <- File.write(normalized_path, content) do
      "成功写入文件 #{normalized_path}"
    else
      {:error, :outside_allowed_roots} ->
        "写入文件 #{path} 失败: 路径不在允许范围内"

      {:error, reason} ->
        "写入文件 #{path} 失败: #{inspect(reason)}"
    end
  end
end
