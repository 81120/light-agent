defmodule Toyagent.Core.Memory.ShortTerm do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get() do
    GenServer.call(__MODULE__, :get)
  end

  def add_item(item) do
    GenServer.call(__MODULE__, {:add, item})
  end

  def add_items(items) do
    GenServer.call(__MODULE__, {:append, items})
  end

  def reset() do
    GenServer.call(__MODULE__, {:reset})
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       short_term_memory: []
     }}
  end

  @impl true
  def handle_call(:get, _from, state) do
    # 滑动窗口，只使用最近的20条记录作为memory
    # TODO, 需要引入一些更精细的 memory 管理策略
    # 例如，
    # 1. 根据消息类型（user/assistant/tool）进行分类，不同类型的消息按不通的策略处理
    # 2. 对一系列联系的 memory 进行压缩，摘要，只保留重要的信息
    # 3. 仿照生物的特性，遗忘一些旧的 memory
    memory =
      Map.get(state, :short_term_memory) |> Enum.take(-20) |> drop_util_user()

    {:reply, memory, state}
  end

  @impl true
  def handle_call({:reset}, _from, _state) do
    {:reply, :ok, %{short_term_memory: []}}
  end

  @impl true
  def handle_call({:add, item}, _from, state) do
    {:reply, :ok,
     Map.update(state, :short_term_memory, [item], &(&1 ++ [item]))}
  end

  @impl true
  def handle_call({:append, items}, _from, state) do
    {:reply, :ok, Map.update(state, :short_term_memory, items, &(&1 ++ items))}
  end

  # 当模型决定调用工具时，对话历史中会产生严格绑定的上下文块：
  # 1. 发起调用：一条 `role: "assistant"` 的消息，其中包含 `tool_calls` 数组
  #   （里面有 `tool_call_id`，例如 `call_abc123`）。
  # 2. 返回结果：紧接着必须是一条或多条 `role: "tool"` 的消息，
  #   并且必须携带对应的 `tool_call_id`，用来把执行结果交还给模型。
  # 3. 寻找最近的 N 条消息中，最靠近边界的 User 消息作为起点。保证
  #   调用工具的上下文块不被截断。
  defp drop_util_user([%{role: "user"} | _] = safe_messages) do
    safe_messages
  end

  defp drop_util_user([_ | tail]) do
    drop_util_user(tail)
  end

  defp drop_util_user([]) do
    []
  end
end
