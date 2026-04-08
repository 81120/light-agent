defmodule LightAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :light_agent,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LightAgent.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.17"},
      {:jason, "~> 1.4"},
      {:env_loader, "~> 0.1.0", only: [:dev, :test]},
      {:ecto, "~> 3.12"},
      {:quantum, "~> 3.5"},
      {:prompt, "~> 0.10.1"}
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
