# LightAgent

A lightweight AI Agent framework built on Elixir/OTP, supporting Tool Calling, multi-session management, and skill extensions.

## Introduction

LightAgent is an AI Agent framework developed in Elixir with the following features:

- **Multi-Session Management**: Create, switch, pause, resume, and delete multiple independent sessions
- **Session Persistence**: Session history is automatically saved to the filesystem, supporting resume from breakpoints
- **CLI Interface**: Rich command-line interface with various interactive commands
- **Tool Calling Support**: Compatible with OpenAI Function Calling protocol
- **Parameter Validation**: Type-safe tool parameter validation based on Ecto Schema
- **Dual-Type Skill System**:
  - **Code-Based Skills**: Defined through Elixir modules, registered at compile time
  - **FS-Based Skills**: Dynamically loaded through the filesystem, supporting runtime extensions
- **Token Usage Tracking**: Real-time tracking and statistics of Token usage
- **Secure Tool Execution**: Sensitive tools require interactive user approval before execution
- **Sequential Tool Execution**: Tool calls are executed one by one in model-returned order

## Architecture

### Overall Architecture

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
│  │  │  │ (API Call)│  │   (Token Statistics) │    │     │ │
│  │  │  └───────────┘  └──────────────────────┘    │     │ │
│  │  └──────────────────────────────────────────────┘     │ │
│  └────────────────────────────────────────────────────────┘ │
│                         │                                    │
│                         ▼                                    │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           LightAgent.Core.Skill.Runner                 │ │
│  │                  (Skill Executor)                      │ │
│  │                                                        │ │
│  │  ┌──────────────────┐  ┌────────────────────────────┐ │ │
│  │  │ CodeBasedSkill   │  │ FsBasedSkill               │ │ │
│  │  │ (Compile-time)   │  │ (Runtime Loading)          │ │ │
│  │  │                  │  │                            │ │ │
│  │  │ ┌──────────────┐ │  │ ┌────────────────────────┐ │ │ │
│  │  │ │ ToolArgs     │ │  │ │ LoadFsSkill            │ │ │ │
│  │  │ │ Validator    │ │  │ │ (Dynamic Loading)      │ │ │ │
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

### Core Components

#### 1. Worker

[worker.ex](lib/light_agent/core/worker.ex) is the core controller of the Agent:

- Runs as a GenServer, maintaining Agent state
- Manages the lifecycle of multiple sessions
- Coordinates LLM calls, session management, and tool execution
- Implements recursive execution loop until task completion

#### 2. Session Management

Adopts a dynamic session architecture:

- **SessionServer**: Independent GenServer for each session, maintaining session state and history
- **SessionMemoryStore**: Responsible for persistent storage of session history using Markdown format
- **SessionSupervisor**: Dynamic supervisor managing all session processes
- **SessionMemoryCompactor**: Periodically compacts session history to optimize storage space

Session Features:

- Support for creating, switching, pausing, resuming, and deleting sessions
- Session history automatically persisted to `agent/session_memory/` directory
- Support for resume from breakpoints, automatic session recovery after application restart

#### 3. Skill System

Supports two types of skills:

**Code-Based Skills**

Defined through Elixir modules using Ecto Schema for parameters:

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

  @doc "Get latitude and longitude for a specified city"
  deftool(:get_location, schema: GetLocationParams)

  @impl true
  def exec(:get_location, %{"city" => city}) do
    # Implementation logic
  end
end
```

**FS-Based Skills**

Defined through the filesystem, supporting dynamic extensions:

```
agent/skills/
└── greet_skill/
    ├── SKILL.md          # Skill description and usage instructions
    └── scripts/
        └── greet.js      # Implementation script
```

**Parameter Validation**

Uses Ecto Changeset for parameter validation:

- Type checking
- Required field validation
- Custom validation rules
- Automatic JSON Schema generation

#### 4. CLI Interface

Provides rich command-line interaction:

- Startup command: `mix light_agent.chat`
- Auto session bootstrap behavior:
  - if only `init` exists, create and switch to a new session
  - if exactly one historical session exists besides `init`, auto-switch to it
  - otherwise restore existing sessions and keep current one

- `/help` - Display help panel
- `/new` - Create and switch to a new session
- `/sessions` - List all sessions
- `/pause` - Pause current session
- `/switch <id>` - Switch to specified session
- `/resume <id>` - Resume specified session
- `/delete <id>` - Delete specified session
- `/history` - Display current session history
- `/usage` - Display Token usage statistics
- `/exit` - Exit program

#### 5. Usage Tracking

Real-time tracking and statistics of Token usage:

- Prompt tokens
- Completion tokens
- Total tokens
- Steps count
- Missing usage steps

### Execution Flow

```
User Input
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
                    │Tool Calls?│
                    └───────────┘
                     │         │
                   Yes        No
                     │         │
                     ▼         ▼
            ┌──────────────┐  ┌──────────┐
            │ Skill.Runner │  │  Return  │
            │ Validate Args│  │  Result  │
            └──────────────┘  └──────────┘
                     │
                     ▼
            ┌──────────────┐
            │ Security     │
            │ Confirmation │
            │ (Prompt UI)  │
            └──────────────┘
                     │
                     ▼
            ┌──────────────┐
            │ Execute Tools│
            │ (Sequential) │
            └──────────────┘
                     │
                     ▼
            ┌──────────────┐
            │    Update    │
            │   History    │
            │  Persist     │
            └──────────────┘
                     │
                     ▼
              Recursive Call
```

## API Usage

### Basic Usage

#### 1. Configure LLM

Create a `.env` file:

```bash
API_KEY=your-api-key
BASE_URL=https://api.openai.com/v1/chat/completions
MODEL=gpt-4
```

Configuration files are automatically loaded (in development and test environments).

#### 2. Start Agent

**Method 1: Using CLI Interface**

```bash
# Start interactive CLI
mix light_agent.chat
```

**Method 2: Programmatic Way**

```elixir
# Start application
{:ok, _pid} = Application.ensure_all_started(:light_agent)

# Run Agent
result = LightAgent.Core.Worker.run_agent("What's the weather in Beijing today?")

# Step-by-step execution
{:running, tool_results, usage} = LightAgent.Core.Worker.run_agent_step("Hello")
{:done, content, usage} = LightAgent.Core.Worker.run_agent_step()
```

### Session Management API

```elixir
# Create new session
{:ok, session_id} = LightAgent.Core.Worker.new_session()

# List all sessions
sessions = LightAgent.Core.Worker.list_sessions()
# [%{id: "init", status: :active, current: true}, ...]

# Switch session
:ok = LightAgent.Core.Worker.switch_session(session_id)

# Pause current session
{:ok, session_id} = LightAgent.Core.Worker.pause_current_session()

# Resume session
:ok = LightAgent.Core.Worker.resume_session(session_id)

# Delete session
{:ok, current_session_id} = LightAgent.Core.Worker.delete_session(session_id)

# View current session history
history = LightAgent.Core.Worker.current_history()

# View Token usage statistics
usage = LightAgent.Core.Worker.current_token_usage()
# %{
#   prompt_tokens: 1000,
#   completion_tokens: 500,
#   total_tokens: 1500,
#   steps: 5,
#   missing_usage_steps: 0
# }
```

### Creating Custom Skills

#### Method 1: Code-Based Skills

Create a new skill module:

```elixir
# lib/light_agent/skills/my_skill.ex
defmodule LightAgent.Skills.MySkill do
  @moduledoc "Skill description"

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

  @doc "Tool description"
  deftool(:my_function, schema: MyFunctionParams)

  @impl true
  def exec(:my_function, %{"param1" => value, "param2" => num}) do
    # Implementation logic
    "Result: #{value}, #{num}"
  end
end
```

Then register in [runner.ex](lib/light_agent/core/skill/runner.ex):

```elixir
def list_skills do
  [
    LightAgent.Skills.Location,
    LightAgent.Skills.Weather,
    LightAgent.Skills.Filesystem,
    LightAgent.Skills.RunCommand,
    LightAgent.Skills.LoadFsSkill,
    LightAgent.Skills.MySkill  # Add new skill
  ]
end
```

#### Method 2: FS-Based Skills

Create skill in `agent/skills/` directory:

```
agent/skills/
└── my_skill/
    ├── SKILL.md
    └── scripts/
        └── main.py
```

**SKILL.md Format:**

```markdown
---
name: my_skill
description: Skill description
---

# My Skill

## Usage Steps

1. Prepare parameters
2. Run script `python scripts/main.py <args>`
3. Process output

## Example

\`\`\`bash
python scripts/main.py "hello"
\`\`\`
```

Use LoadFsSkill tool to dynamically load:

```elixir
LightAgent.Skills.LoadFsSkill.exec(:load_fs_skill, %{"skill_name" => "my_skill"})
```

### Built-in Skills

#### Location

- `get_location(city)` - Get city latitude and longitude

#### Weather

- `get_weather(latitude, longitude)` - Get weather for specified location

#### Filesystem

- `read_file(path)` - Read file content
- `write_file(path, content)` - Write to file

#### RunCommand

- `run_command(command)` - Execute shell command

#### LoadFsSkill

- `load_fs_skill(skill_name)` - Dynamically load filesystem-based skill

### LLM Call API

```elixir
# Direct LLM call
messages = [
  %{"role" => "system", "content" => "You are an assistant"},
  %{"role" => "user", "content" => "Hello"}
]

tools = LightAgent.Core.Skill.Runner.build_tools_schema()

{:ok, response} = LightAgent.Core.LLM.call(messages, tools)
```

## Configuration

### Agent Configuration

Configure in `config/config.exs`:

```elixir
import Config

config :light_agent, :agent_external_root, "agent"
```

### LLM Configuration

Configure in `.env` file:

```bash
API_KEY=your-api-key
BASE_URL=https://api.openai.com/v1/chat/completions
MODEL=gpt-4
```

### Agent Context Configuration

Configure Agent context in `agent/config/` directory:

- `SOUL.md` - Agent role and personality definition
- `USER.md` - User information and preferences
- `MEMORY.md` - Long-term memory and knowledge base
- `AGENT.md` - Agent capabilities and limitations

These files are automatically loaded into the session's system prompt.

## Dependencies

- **Elixir** ~> 1.19
- **Req** ~> 0.5.17 (HTTP Client)
- **Jason** ~> 1.4 (JSON Parsing)
- **Ecto** ~> 3.12 (Data Validation)
- **EnvLoader** ~> 0.1.0 (Environment Variable Loading)
- **Prompt** ~> 0.10.1 (Interactive approval prompts)

## Installation and Running

```bash
# Get dependencies
mix deps.get

# Configure environment variables
cp .env.example .env
# Edit .env file and fill in your API configuration

# Start interactive CLI
mix light_agent.chat

# Or run Agent directly in IEx
iex -S mix
iex> LightAgent.Core.Worker.run_agent("Hello")
```

## Project Structure

```
light-agent/
├── lib/
│   └── light_agent/
│       ├── application.ex              # OTP application entry
│       ├── cli/
│       │   ├── command_router.ex       # CLI command router
│       │   ├── input_reader.ex         # Input reader
│       │   ├── prompts.ex              # Prompt-based interactive confirmations
│       │   └── status_formatter.ex     # Status formatter
│       ├── core/
│       │   ├── LLM.ex                  # LLM API calls
│       │   ├── worker.ex               # Agent worker
│       │   ├── agent_paths.ex          # Path management
│       │   ├── session_server.ex       # Session server
│       │   ├── session_supervisor.ex   # Session supervisor
│       │   ├── session_memory_store.ex # Session memory store
│       │   ├── session_memory_compactor.ex # Session memory compactor
│       │   ├── worker/
│       │   │   ├── session.ex          # Session helpers
│       │   │   └── usage.ex            # Token usage statistics
│       │   └── skill/
│       │       ├── code_based_skill.ex      # Code-based skill macro
│       │       ├── fs_based_skill.ex        # Filesystem-based skill
│       │       ├── runner.ex                # Skill executor
│       │       ├── tool_args_validator.ex   # Parameter validator
│       │       └── schema_json_schema.ex    # Schema converter
│       └── skills/
│           ├── filesystem.ex           # File operation skill
│           ├── location.ex             # Location query skill
│           ├── run_command.ex          # Command execution skill
│           ├── weather.ex              # Weather query skill
│           └── load_fs_skill.ex        # Dynamic skill loader
├── agent/
│   ├── config/                         # Agent configuration directory
│   │   ├── SOUL.md                     # Agent role
│   │   ├── USER.md                     # User information
│   │   ├── MEMORY.md                   # Long-term memory
│   │   └── AGENT.md                    # Agent capabilities
│   ├── session_memory/                 # Session history storage
│   │   ├── session-init.md
│   │   └── session-<uuid>.md
│   └── skills/                         # Filesystem-based skills directory
│       └── greet_skill/
│           ├── SKILL.md
│           └── scripts/
│               └── greet.js
├── config/
│   ├── config.exs                      # Application configuration
│   └── runtime.exs                     # Runtime configuration
├── test/                               # Test files
├── mix.exs                             # Project definition
└── README.md
```

## Testing

The project includes comprehensive test cases:

```bash
# Run all tests
mix test

# Run specific test
mix test test/light_agent/core/worker/session_test.exs

# Run tests with detailed output
mix test --trace
```

Test coverage:

- Session management (Session, SessionServer, SessionMemoryStore)
- Skill system (CodeBasedSkill, ToolArgsValidator, SchemaJsonSchema)
- Built-in skills (Location, Weather, Filesystem, RunCommand)
- Usage statistics (Usage)
- Path management (AgentPaths)

## Extension Suggestions

1. **Session Compression Optimization**: Implement smarter session history compression strategies
2. **Streaming Output**: Support LLM streaming responses for better user experience
3. **Multi-modal Support**: Support image, audio, and other multi-modal inputs
4. **Skill Marketplace**: Build a skill sharing and download platform
5. **Plugin System**: Improve execution environment and security isolation for FS-Based Skills
6. **Distributed Support**: Support multi-node deployment and session synchronization
7. **Monitoring and Logging**: Enhance monitoring and logging systems for easier debugging and optimization

## License

MIT
