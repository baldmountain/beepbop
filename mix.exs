defmodule BeepBop.MixProject do
  use Mix.Project

  def project do
    [
      app: :beepbop,
      version: "0.0.1",
      elixir: ">= 1.5.3",
      description: description(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.json": :test, "coveralls.html": :test]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:credo_contrib, "~> 0.2", only: :dev, runtime: false},
      {:excoveralls, "~> 0.14", only: :test},
      {:ecto_sql, "~> 3.6"},
      {:postgrex, "~> 0.15", only: :test},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "State Machine DSL for elixir. Could be useful, maybe."
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
