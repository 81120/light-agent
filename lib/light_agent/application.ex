defmodule LightAgent.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, args) do
    children = [
      # Starts a worker by calling: LightAgent.Core.Worker.start_link(arg)
      {Registry, keys: :unique, name: LightAgent.Core.SessionRegistry},
      {LightAgent.Core.SessionSupervisor, []},
      {LightAgent.Core.Worker, args},
      {LightAgent.Core.Scheduler, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LightAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
