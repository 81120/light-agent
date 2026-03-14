defmodule Toyagent.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, args) do
    children = [
      # Starts a worker by calling: Toyagent.Core.Worker.start_link(arg)
      {Toyagent.Core.Memory.LongTerm, []},
      {Toyagent.Core.Memory.ShortTerm, []},
      {Toyagent.Core.Worker, args}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Toyagent.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
