defmodule LightAgent.Core.Skill.CodeBasedSkill do
  @callback exec(tool_name :: atom(), args :: map()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour LightAgent.Core.Skill.CodeBasedSkill

      import LightAgent.Core.Skill.CodeBasedSkill
      require Logger
      # 注册属性，用于存储工具定义
      Module.register_attribute(__MODULE__, :tools, accumulate: true)
      @before_compile LightAgent.Core.Skill.CodeBasedSkill
    end
  end

  defmacro deftool(name, schema: param_schema) do
    quote bind_quoted: [name: name, param_schema: param_schema] do
      case Code.ensure_compiled(param_schema) do
        {:module, _} ->
          :ok

        {:error, _} ->
          raise CompileError,
            description:
              "deftool #{name}: schema #{inspect(param_schema)} is not available at compile time"
      end

      unless function_exported?(param_schema, :changeset, 1) do
        raise CompileError,
          description:
            "deftool #{name}: schema #{inspect(param_schema)} must implement changeset/1"
      end

      @tools %{
        name: name,
        description: @doc,
        param_schema: param_schema,
        function: name
      }

      def unquote(name)(args) do
        Logger.debug(
          "Calling tool #{unquote(name)} with args: #{inspect(args)}"
        )

        exec(unquote(name), args)
      end
    end
  end

  # 编译前钩子：生成统一的定义获取函数
  defmacro __before_compile__(_env) do
    quote do
      def __skill_definition__ do
        %{
          name: __MODULE__ |> Module.split() |> List.last(),
          description: @moduledoc,
          tools: @tools
        }
      end
    end
  end
end
