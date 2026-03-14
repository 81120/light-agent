defmodule LightAgent.Core.Memory.LongTerm do
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
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       long_term_memory: []
     }}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, Map.get(state, :long_term_memory), state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{long_term_memory: []}}
  end

  @impl true
  def handle_call({:add, item}, _from, state) do
    {:reply, :ok, Map.update(state, :long_term_memory, [item], &(&1 ++ [item]))}
  end

  @impl true
  def handle_call({:append, items}, _from, state) do
    {:reply, :ok, Map.update(state, :long_term_memory, items, &(&1 ++ items))}
  end
end
