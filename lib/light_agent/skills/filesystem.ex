defmodule LightAgent.Skills.Filesystem do
  @moduledoc "提供文件系统操作能力的技能包"

  use LightAgent.Core.Skill.CodeBasedSkill

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
    case File.read(path) do
      {:ok, content} ->
        content

      {:error, reason} ->
        "读取文件 #{path} 失败: #{inspect(reason)}"
    end
  end

  @doc "写入内容到指定文件"
  deftool(:write_file, schema: WriteFileParams)

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
