defmodule LightAgent.Skills.Filesystem do
  @moduledoc "Skill package for filesystem operations."

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

  @doc "Read file content from a path."
  deftool(:read_file, schema: ReadFileParams)

  @impl true
  def exec(:read_file, %{"path" => path}) do
    with {:ok, normalized_path} <- AgentPaths.normalize_and_authorize_path(path),
         {:ok, content} <- File.read(normalized_path) do
      content
    else
      {:error, :outside_allowed_roots} ->
        "Failed to read file #{path}: path is outside allowed roots"

      {:error, reason} ->
        "Failed to read file #{path}: #{inspect(reason)}"
    end
  end

  @doc "Write content to a file path."
  deftool(:write_file, schema: WriteFileParams)

  @impl true
  def exec(:write_file, %{"path" => path, "content" => content}) do
    with {:ok, normalized_path} <- AgentPaths.normalize_and_authorize_path(path),
         :ok <- File.write(normalized_path, content) do
      "Successfully wrote file #{normalized_path}"
    else
      {:error, :outside_allowed_roots} ->
        "Failed to write file #{path}: path is outside allowed roots"

      {:error, reason} ->
        "Failed to write file #{path}: #{inspect(reason)}"
    end
  end
end
