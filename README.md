# LightAgent

一个轻量级的 AI Agent 框架，基于 Elixir/OTP 构建，支持工具调用（Tool Calling）和技能扩展。

## 项目介绍

LightAgent 是一个使用 Elixir 语言开发的 AI Agent 框架，具有以下特点：

- **轻量级设计**：基于 OTP 的简洁架构，易于理解和扩展
- **工具调用支持**：支持 OpenAI 兼容的 Function Calling 协议
- **双类型技能系统**：
  - **代码型技能（Code-Based Skills）**：通过 Elixir 模块定义，编译时注册
  - **文件系统型技能（FS-Based Skills）**：通过文件系统动态加载，支持运行时扩展
- **智能记忆管理**：分层记忆系统，支持短期记忆和长期记忆
- **并发执行**：工具调用支持并发执行，提升效率

## 设计架构

### 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    LightAgent.Application               │
│                    (OTP Application)                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │           LightAgent.Core.Worker                │   │
│  │              (GenServer)                        │   │
│  │                                                 │   │
│  │  ┌─────────────┐    ┌──────────────────────┐   │   │
│  │  │    LLM      │◄───│      Memory          │   │   │
│  │  │  (API调用)  │    │  ┌────────────────┐  │   │   │
│  │  └─────────────┘    │  │  ShortTerm     │  │   │   │
│  │                     │  │  (滑动窗口)    │  │   │   │
│  │                     │  ├────────────────┤  │   │   │
│  │                     │  │  LongTerm      │  │   │   │
│  │                     │  │  (系统提示)    │  │   │   │
│  │                     │  └────────────────┘  │   │   │
│  │                     └──────────────────────┘   │   │
│  └─────────────────────────────────────────────────┘   │
│                         │                              │
│                         ▼                              │
│  ┌─────────────────────────────────────────────────┐   │
│  │         LightAgent.Core.Skill.Runner            │   │
│  │              (技能执行器)                        │   │
│  │                                                 │   │
│  │  ┌───────────────────┐  ┌───────────────────┐  │   │
│  │  │ CodeBasedSkill    │  │ FsBasedSkill      │  │   │
│  │  │ (编译时注册)      │  │ (运行时加载)      │  │   │
│  │  └───────────────────┘  └───────────────────┘  │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 核心组件

#### 1. Worker（工作器）

[worker.ex](lib/light_agent/core/worker.ex) 是 Agent 的核心控制器：

- 作为 GenServer 运行，维护 Agent 状态
- 协调 LLM 调用、记忆管理和工具执行
- 实现递归执行循环，直到任务完成

#### 2. Memory（记忆系统）

采用分层记忆架构：

- **LongTerm（长期记忆）**：存储系统提示和持久化信息
- **ShortTerm（短期记忆）**：存储对话历史，采用滑动窗口策略（最近 20 条）
- **All**：合并长期和短期记忆，提供给 LLM

#### 3. Skill System（技能系统）

支持两种技能类型：

**Code-Based Skills（代码型技能）**

通过 Elixir 模块定义，使用 `deftool` 宏声明工具：

```elixir
defmodule LightAgent.Skills.Weather do
  use LightAgent.Core.Skill.CodeBasedSkill

  @doc "获取指定经纬度的当前天气"
  deftool(:get_weather, %{
    type: "object",
    properties: %{
      latitude: %{type: "number", description: "纬度"},
      longitude: %{type: "number", description: "经度"}
    },
    required: ["latitude", "longitude"]
  })

  @impl true
  def exec(:get_weather, %{"latitude" => lat, "longitude" => lng}) do
    # 实现逻辑
  end
end
```

**FS-Based Skills（文件系统型技能）**

通过文件系统定义，支持动态扩展：

```
.agent/skills/
└── greet_skill/
    ├── SKILL.md          # 技能描述和使用说明
    └── scripts/
        └── greet.js      # 实现脚本
```

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
┌─────────────┐     ┌──────────────┐
│ Memory.All  │────►│  LLM.call()  │
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
            │ 更新 Memory  │
            └──────────────┘
                     │
                     ▼
                递归调用
```

## API 用法

### 基本使用

#### 1. 配置 LLM

在 `config/config.exs` 中配置 LLM API：

```elixir
import Config

config :light_agent, Core.LLM,
  api_key: "your-api-key",
  base_url: "https://api.openai.com/v1/chat/completions",
  model: "gpt-4"
```

#### 2. 启动 Agent

```elixir
# 启动应用
{:ok, _pid} = Application.ensure_all_started(:light_agent)

# 运行 Agent
result = LightAgent.Core.Worker.run_agent("北京今天天气怎么样？")
```

### 创建自定义技能

#### 方式一：代码型技能

创建新的技能模块：

```elixir
# lib/light_agent/skills/my_skill.ex
defmodule LightAgent.Skills.MySkill do
  @moduledoc "技能描述"

  use LightAgent.Core.Skill.CodeBasedSkill

  @doc "工具描述"
  deftool(:my_function, %{
    type: "object",
    properties: %{
      param1: %{type: "string", description: "参数描述"}
    },
    required: ["param1"]
  })

  @impl true
  def exec(:my_function, %{"param1" => value}) do
    # 实现逻辑
    "处理结果: #{value}"
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
    LightAgent.Skills.MySkill  # 添加新技能
  ]
end
```

#### 方式二：文件系统型技能

在 `.agent/skills/` 目录下创建技能：

```
.agent/skills/
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

### 内置技能

#### Location（位置查询）

- `get_location(city)` - 获取城市经纬度

#### Weather（天气查询）

- `get_weather(latitude, longitude)` - 获取指定位置的天气
- `get_clothing_recommendation(temperature)` - 根据温度推荐服装

#### Filesystem（文件操作）

- `read_file(path)` - 读取文件内容
- `write_file(path, content)` - 写入文件

#### RunCommand（命令执行）

- `run_command(command)` - 执行 shell 命令

### 记忆管理 API

```elixir
# 短期记忆
LightAgent.Core.Memory.ShortTerm.add_item(%{role: "user", content: "hello"})
LightAgent.Core.Memory.ShortTerm.get()
LightAgent.Core.Memory.ShortTerm.reset()

# 长期记忆
LightAgent.Core.Memory.LongTerm.add_item(%{role: "system", content: "系统提示"})
LightAgent.Core.Memory.LongTerm.get()
LightAgent.Core.Memory.LongTerm.reset()

# 获取所有记忆
LightAgent.Core.Memory.All.get()
```

### LLM 调用 API

```elixir
# 直接调用 LLM
messages = [
  %{role: "system", content: "你是一个助手"},
  %{role: "user", content: "你好"}
]

tools = [
  %{
    type: "function",
    function: %{
      name: "get_weather",
      description: "获取天气",
      parameters: %{type: "object", properties: %{}}
    }
  }
]

response = LightAgent.Core.LLM.call(messages, tools)
```

## 依赖

- **Elixir** ~> 1.19
- **Req** ~> 0.5.17（HTTP 客户端）
- **Jason** ~> 1.4（JSON 解析）

## 安装与运行

```bash
# 获取依赖
mix deps.get

# 启动交互式环境
iex -S mix

# 运行示例
iex> LightAgent.Core.Worker.run_agent("你好")
```

## 项目结构

```
light-agent/
├── lib/
│   └── light_agent/
│       ├── application.ex          # OTP 应用入口
│       ├── core/
│       │   ├── LLM.ex              # LLM API 调用
│       │   ├── worker.ex           # Agent 工作器
│       │   ├── memory/
│       │   │   ├── all.ex          # 记忆合并
│       │   │   ├── long_term.ex    # 长期记忆
│       │   │   └── short_term.ex   # 短期记忆
│       │   └── skill/
│       │       ├── code_based_skill.ex  # 代码型技能宏
│       │       ├── fs_based_skill.ex    # 文件系统型技能
│       │       └── runner.ex            # 技能执行器
│       └── skills/
│           ├── filesystem.ex       # 文件操作技能
│           ├── location.ex         # 位置查询技能
│           ├── run_command.ex      # 命令执行技能
│           └── weather.ex          # 天气查询技能
├── .agent/
│   └── skills/                     # 文件系统型技能目录
│       └── greet_skill/
│           ├── SKILL.md
│           └── scripts/
│               └── greet.js
├── config/
│   └── config.exs                  # 配置文件
├── mix.exs                         # 项目定义
└── README.md
```

## 扩展建议

1. **记忆优化**：实现更精细的记忆管理策略，如记忆压缩、重要性排序
2. **错误处理**：增强工具调用的错误处理和重试机制
3. **流式输出**：支持 LLM 流式响应
4. **多模态**：支持图像、音频等多模态输入
5. **插件系统**：完善 FS-Based Skills 的执行环境

## License

MIT
