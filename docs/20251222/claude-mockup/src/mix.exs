defmodule XTrack.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/xtrack"

  def project do
    [
      app: :xtrack,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {XTrack.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},

      # Optional: Postgres storage
      {:ecto_sql, "~> 3.10", optional: true},
      {:postgrex, "~> 0.17", optional: true},

      # Dev/Test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Cross-language ML experiment tracking protocol and runtime.
    Transport-agnostic IR for tracking experiments between Python and Elixir.
    """
  end

  defp package do
    [
      name: "xtrack",
      files: ~w(lib python .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "XTrack",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
