# LightAgent

一个轻量级的 AI Agent 框架，基于 Elixir/OTP 构建，支持工具调用（Tool Calling）、多会话管理和技能扩展。

## 项目介绍

LightAgent 是一个使用 Elixir 语言开发的 AI Agent 框架，具有以下特点：

- **多会话管理**：支持创建、切换、暂停、恢复和删除多个独立会话
- **会话持久化**：会话历史自动保存到文件系统，支持断点续聊
- **CLI 界面**：提供丰富的命令行界面，支持多种交互命令
- **工具调用支持**：支持 OpenAI 兼容的 Function Calling 协议
- **参数验证**：基于 Ecto Schema 的工具参数验证，确保类型安全
- **双类型技能系统**：
  - **代码型技能（Code-Based Skills）**：通过 Elixir 模块定义，编译时注册
  - **文件系统型技能（FS-Based Skills）**：通过文件系统动态加载，支持运行时扩展
- **Token 使用统计**：实时跟踪和统计 Token 使用情况
- **并发执行**：工具调用支持并发执行，提升效率

## 设计架构

### 整体架构

```
┌──────────────────────────────────────────────────────────────┐
│                    LightAgent.Application                    │
│                    (OTP Application)                         │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              LightAgent.Core.Worker                    │ │
│  │                (GenServer)                             │ │
│  │                                                        │ │
│  │  ┌──────────────────────────────────────────────┐     │ │
│  │  │         Session Management                   │     │ │
│  │  │  ┌──────────────┐  ┌───────────────────┐    │     │ │
│  │  │  │ SessionServer│  │ SessionMemoryStore│    │     │ │
│  │  │  │  (Per Session)│  │  (Persistence)    │    │     │ │
│  │  │  └──────────────┘  └───────────────────┘    │     │ │
│  │  └──────────────────────────────────────────────┘     │ │
│  │                         │                              │ │
│  │  ┌──────────────────────────────────────────────┐     │ │
│  │  │              LLM & Usage                     │     │ │
│  │  │  ┌───────────┐  ┌──────────────────────┐    │     │ │
│  │  │  │    LLM    │  │    Usage Tracking    │    │     │ │
│  │  │  │ (API调用) │  │   (Token 统计)       │    │     │ │
│  │  │  └───────────┘  └──────────────────────┘    │     │ │
│  │  └──────────────────────────────────────────────┘     │ │
│  └────────────────────────────────────────────────────────┘ │
│                         │                                    │
│                         ▼                                    │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           LightAgent.Core.Skill.Runner                 │ │
│  │                  (技能执行器)                           │ │
│  │                                                        │ │
│  │  ┌──────────────────┐  ┌────────────────────────────┐ │ │
│  │  │ CodeBasedSkill   │  │ FsBasedSkill               │ │ │
│  │  │ (编译时注册)     │  │ (运行时加载)               │ │ │
│  │  │                  │  │                            │ │ │
│  │  │ ┌──────────────┐ │  │ ┌────────────────────────┐ │ │ │
│  │  │ │ ToolArgs     │ │  │ │ LoadFsSkill            │ │ │ │
│  │  │ │ Validator    │ │  │ │ (动态加载)             │ │ │ │
│  │  │ └──────────────┘ │  │ └────────────────────────┘ │ │ │
│  │  └──────────────────┘  └────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    CLI Interface                       │ │
│  │  ┌───────────────┐  ┌──────────────┐  ┌────────────┐  │ │
│  │  │CommandRouter  │  │ InputReader  │  │StatusFormat│  │ │
│  │  └───────────────┘  └──────────────┘  └────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 核心组件

#### 1. Worker（工作器）

[worker.ex](lib/light_agent/core/worker.ex) 是 Agent 的核心控制器：

- 作为 GenServer 运行，维护 Agent 状态
- 管理多个会话的生命周期
- 协调 LLM 调用、会话管理和工具执行
- 实现递归执行循环，直到任务完成

#### 2. Session Management（会话管理）

采用动态会话架构：

- **SessionServer**：每个会话独立运行的 GenServer，维护会话状态和历史
- **SessionMemoryStore**：负责会话历史的持久化存储，使用 Markdown 格式
- **SessionSupervisor**：动态监督器，管理所有会话进程
- **SessionMemoryCompactor**：定期压缩会话历史，优化存储空间

会话特性：

- 支持创建、切换、暂停、恢复、删除会话
- 会话历史自动持久化到 `agent/session_memory/` 目录
- 支持断点续聊，重启应用后自动恢复会话

#### 3. Skill System（技能系统）

支持两种技能类型：

**Code-Based Skills（代码型技能）**

通过 Elixir 模块定义，使用 Ecto Schema 定义参数：

```elixir
defmodule LightAgent.Skills.Location do
  use LightAgent.Core.Skill.CodeBasedSkill

  defmodule GetLocationParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:city, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:city])
      |> validate_required([:city])
    end

    def required_fields, do: [:city]
  end

  @doc "获取指定城市的经纬度"
  deftool(:get_location, schema: GetLocationParams)

  @impl true
  def exec(:get_location, %{"city" => city}) do
    # 实现逻辑
  end
end
```

**FS-Based Skills（文件系统型技能）**

通过文件系统定义，支持动态扩展：

```
agent/skills/
└── greet_skill/
    ├── SKILL.md          # 技能描述和使用说明
    └── scripts/
        └── greet.js      # 实现脚本
```

**参数验证**

使用 Ecto Changeset 进行参数验证：

- 类型检查
- 必填字段验证
- 自定义验证规则
- 自动生成 JSON Schema

#### 4. CLI Interface（命令行界面）

提供丰富的命令行交互：

- `/help` - 显示帮助面板
- `/new` - 创建并切换到新会话
- `/sessions` - 列出所有会话
- `/pause` - 暂停当前会话
- `/switch <id>` - 切换到指定会话
- `/resume <id>` - 恢复指定会话
- `/delete <id>` - 删除指定会话
- `/history` - 显示当前会话历史
- `/usage` - 显示 Token 使用统计
- `/exit` - 退出程序

#### 5. Usage Tracking（使用统计）

实时跟踪和统计 Token 使用情况：

- Prompt tokens
- Completion tokens
- Total tokens
- Steps count
- Missing usage steps

### 执行流程

```
用户输入
    │
    ▼
┌─────────────┐
│   Worker    │
└─────────────┘
    │
    ▼
┌──────────────────┐
│ SessionServer    │
│ (Current Session)│
└──────────────────┘
    │
    ▼
┌─────────────┐     ┌──────────────┐
│   History   │────►│  LLM.call()  │
└─────────────┘     └──────────────┘
                          │
                          ▼
                    ┌───────────┐
                    │ 有工具调用？│
                    └───────────┘
                     │         │
                    是        否
                     │         │
                     ▼         ▼
            ┌──────────────┐  ┌──────────┐
            │ Skill.Runner │  │ 返回结果 │
            │  执行工具    │  └──────────┘
            └──────────────┘
                     │
                     ▼
            ┌──────────────┐
            │ 参数验证     │
            └──────────────┘
                     │
                     ▼
            ┌──────────────┐
            │ 更新 History │
            │ 持久化会话   │
            └──────────────┘
                     │
                     ▼
                递归调用
```

## API 用法

### 基本使用

#### 1. 配置 LLM

创建 `.env` 文件：

```bash
API_KEY=your-api-key
BASE_URL=https://api.openai.com/v1/chat/completions
MODEL=gpt-4
```

配置文件会自动加载（开发环境和测试环境）。

#### 2. 启动 Agent

**方式一：使用 CLI 界面**

```bash
# 启动交互式 CLI
iex -S mix

# 在 CLI 中输入
iex> LightAgent.CLI.CommandRouter.start()
```

**方式二：编程方式**

```elixir
# 启动应用
{:ok, _pid} = Application.ensure_all_started(:light_agent)

# 运行 Agent
result = LightAgent.Core.Worker.run_agent("北京今天天气怎么样？")

# 分步执行
{:running, tool_results, usage} = LightAgent.Core.Worker.run_agent_step("你好")
{:done, content, usage} = LightAgent.Core.Worker.run_agent_step()
```

### 会话管理 API

```elixir
# 创建新会话
{:ok, session_id} = LightAgent.Core.Worker.new_session()

# 列出所有会话
sessions = LightAgent.Core.Worker.list_sessions()
# [%{id: "init", status: :active, current: true}, ...]

# 切换会话
:ok = LightAgent.Core.Worker.switch_session(session_id)

# 暂停当前会话
{:ok, session_id} = LightAgent.Core.Worker.pause_current_session()

# 恢复会话
:ok = LightAgent.Core.Worker.resume_session(session_id)

# 删除会话
{:ok, current_session_id} = LightAgent.Core.Worker.delete_session(session_id)

# 查看当前会话历史
history = LightAgent.Core.Worker.current_history()

# 查看 Token 使用统计
usage = LightAgent.Core.Worker.current_token_usage()
# %{
#   prompt_tokens: 1000,
#   completion_tokens: 500,
#   total_tokens: 1500,
#   steps: 5,
#   missing_usage_steps: 0
# }
```

### 创建自定义技能

#### 方式一：代码型技能

创建新的技能模块：

```elixir
# lib/light_agent/skills/my_skill.ex
defmodule LightAgent.Skills.MySkill do
  @moduledoc "技能描述"

  use LightAgent.Core.Skill.CodeBasedSkill

  defmodule MyFunctionParams do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:param1, :string)
      field(:param2, :integer)
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:param1, :param2])
      |> validate_required([:param1])
      |> validate_number(:param2, greater_than: 0)
    end

    def required_fields, do: [:param1]
  end

  @doc "工具描述"
  deftool(:my_function, schema: MyFunctionParams)

  @impl true
  def exec(:my_function, %{"param1" => value, "param2" => num}) do
    # 实现逻辑
    "处理结果: #{value}, #{num}"
  end
end
```

然后在 [runner.ex](lib/light_agent/core/skill/runner.ex) 中注册：

```elixir
def list_skills do
  [
    LightAgent.Skills.Location,
    LightAgent.Skills.Weather,
    LightAgent.Skills.Filesystem,
    LightAgent.Skills.RunCommand,
    LightAgent.Skills.LoadFsSkill,
    LightAgent.Skills.MySkill  # 添加新技能
  ]
end
```

#### 方式二：文件系统型技能

在 `agent/skills/` 目录下创建技能：

```
agent/skills/
└── my_skill/
    ├── SKILL.md
    └── scripts/
        └── main.py
```

**SKILL.md 格式：**

```markdown
---
name: my_skill
description: 技能描述
---

# My Skill

## 使用步骤

1. 准备参数
2. 运行脚本 `python scripts/main.py <args>`
3. 处理输出

## 示例

\`\`\`bash
python scripts/main.py "hello"
\`\`\`
```

使用 LoadFsSkill 工具动态加载：

```elixir
LightAgent.Skills.LoadFsSkill.exec(:load_fs_skill, %{"skill_name" => "my_skill"})
```

### 内置技能

#### Location（位置查询）

- `get_location(city)` - 获取城市经纬度

#### Weather（天气查询）

- `get_weather(latitude, longitude)` - 获取指定位置的天气

#### Filesystem（文件操作）

- `read_file(path)` - 读取文件内容
- `write_file(path, content)` - 写入文件

#### RunCommand（命令执行）

- `run_command(command)` - 执行 shell 命令

#### LoadFsSkill（动态加载技能）

- `load_fs_skill(skill_name)` - 动态加载文件系统型技能

### LLM 调用 API

```elixir
# 直接调用 LLM
messages = [
  %{"role" => "system", "content" => "你是一个助手"},
  %{"role" => "user", "content" => "你好"}
]

tools = LightAgent.Core.Skill.Runner.build_tools_schema()

{:ok, response} = LightAgent.Core.LLM.call(messages, tools)
```

## 配置

### Agent 配置

在 `config/config.exs` 中配置：

```elixir
import Config

config :light_agent, :agent_external_root, "agent"
```

### LLM 配置

在 `.env` 文件中配置：

```bash
API_KEY=your-api-key
BASE_URL=https://api.openai.com/v1/chat/completions
MODEL=gpt-4
```

### Agent 上下文配置

在 `agent/config/` 目录下配置 Agent 的上下文：

- `SOUL.md` - Agent 的角色和性格定义
- `USER.md` - 用户信息和偏好
- `MEMORY.md` - 长期记忆和知识库
- `AGENT.md` - Agent 的能力和限制说明

这些文件会自动加载到会话的系统提示中。

## 依赖

- **Elixir** ~> 1.19
- **Req** ~> 0.5.17（HTTP 客户端）
- **Jason** ~> 1.4（JSON 解析）
- **Ecto** ~> 3.12（数据验证）
- **EnvLoader** ~> 0.1.0（环境变量加载）

## 安装与运行

```bash
# 获取依赖
mix deps.get

# 配置环境变量
cp .env.example .env
# 编辑 .env 文件，填入你的 API 配置

# 启动交互式环境
iex -S mix

# 运行 CLI
iex> LightAgent.CLI.CommandRouter.start()

# 或直接运行 Agent
iex> LightAgent.Core.Worker.run_agent("你好")
```

## 项目结构

```
light-agent/
├── lib/
│   └── light_agent/
│       ├── application.ex              # OTP 应用入口
│       ├── cli/
│       │   ├── command_router.ex       # CLI 命令路由
│       │   ├── input_reader.ex         # 输入读取器
│       │   └── status_formatter.ex     # 状态格式化
│       ├── core/
│       │   ├── LLM.ex                  # LLM API 调用
│       │   ├── worker.ex               # Agent 工作器
│       │   ├── agent_paths.ex          # 路径管理
│       │   ├── session_server.ex       # 会话服务器
│       │   ├── session_supervisor.ex   # 会话监督器
│       │   ├── session_memory_store.ex # 会话内存存储
│       │   ├── session_memory_compactor.ex # 会话内存压缩
│       │   ├── worker/
│       │   │   ├── session.ex          # 会话辅助函数
│       │   │   └── usage.ex            # Token 使用统计
│       │   └── skill/
│       │       ├── code_based_skill.ex      # 代码型技能宏
│       │       ├── fs_based_skill.ex        # 文件系统型技能
│       │       ├── runner.ex                # 技能执行器
│       │       ├── tool_args_validator.ex   # 参数验证器
│       │       └── schema_json_schema.ex    # Schema 转换器
│       └── skills/
│           ├── filesystem.ex           # 文件操作技能
│           ├── location.ex             # 位置查询技能
│           ├── run_command.ex          # 命令执行技能
│           ├── weather.ex              # 天气查询技能
│           └── load_fs_skill.ex        # 动态加载技能
├── agent/
│   ├── config/                         # Agent 配置目录
│   │   ├── SOUL.md                     # Agent 角色
│   │   ├── USER.md                     # 用户信息
│   │   ├── MEMORY.md                   # 长期记忆
│   │   └── AGENT.md                    # Agent 能力
│   ├── session_memory/                 # 会话历史存储
│   │   ├── session-init.md
│   │   └── session-<uuid>.md
│   └── skills/                         # 文件系统型技能目录
│       └── greet_skill/
│           ├── SKILL.md
│           └── scripts/
│               └── greet.js
├── config/
│   ├── config.exs                      # 应用配置
│   └── runtime.exs                     # 运行时配置
├── test/                               # 测试文件
├── mix.exs                             # 项目定义
└── README.md
```

## 测试

项目包含完整的测试用例：

```bash
# 运行所有测试
mix test

# 运行特定测试
mix test test/light_agent/core/worker/session_test.exs

# 运行带详细输出的测试
mix test --trace
```

测试覆盖：

- 会话管理（Session, SessionServer, SessionMemoryStore）
- 技能系统（CodeBasedSkill, ToolArgsValidator, SchemaJsonSchema）
- 内置技能（Location, Weather, Filesystem, RunCommand）
- 使用统计（Usage）
- 路径管理（AgentPaths）

## 扩展建议

1. **会话压缩优化**：实现更智能的会话历史压缩策略
2. **流式输出**：支持 LLM 流式响应，提升用户体验
3. **多模态支持**：支持图像、音频等多模态输入
4. **技能市场**：构建技能分享和下载平台
5. **插件系统**：完善 FS-Based Skills 的执行环境和安全隔离
6. **分布式支持**：支持多节点部署和会话同步
7. **监控和日志**：增强监控和日志系统，便于调试和优化

## License

MIT
