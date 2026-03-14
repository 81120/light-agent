defmodule Toyagent.Core.Skill.CodeBasedSkill do
  @callback exec(tool_name :: atom(), args :: map()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Toyagent.Core.Skill.CodeBasedSkill

      import Toyagent.Core.Skill.CodeBasedSkill
      require Logger
      # 注册属性，用于存储工具定义
      Module.register_attribute(__MODULE__, :tools, accumulate: true)
      @before_compile Toyagent.Core.Skill.CodeBasedSkill
    end
  end

  defmacro deftool(name, parameters) do
    quote do
      # 1. 将工具元数据存入模块属性
      @tools %{
        name: unquote(name),
        # description: unquote(description),
        description: @doc,
        parameters: unquote(parameters),
        function: unquote(name)
      }

      # 2. 定义实际函数
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
