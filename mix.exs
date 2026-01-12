defmodule SnakeBridge.MixProject do
  use Mix.Project

  @version "0.8.3"
  @source_url "https://github.com/nshkrdotcom/snakebridge"

  def project do
    [
      app: :snakebridge,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [~r{^test/fixtures/}],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "SnakeBridge",
      description: "Compile-time generator for type-safe Elixir bindings to Python libraries",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package(),

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SnakeBridge.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core - Python bridge
      {:snakepit, "~> 0.10.1"},

      # JSON encoding
      {:jason, "~> 1.4"},
      # Telemetry
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},

      # Development & Testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:supertester, "~> 0.5.1", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "SnakeBridge",
      source_ref: "v#{@version}",
      source_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/snakebridge.svg",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        {"guides/SESSION_AFFINITY.md", [title: "Session Affinity", filename: "session-affinity"]},
        # Examples
        {"examples/README.md", [title: "Examples Overview", filename: "examples-overview"]},
        {"examples/math_demo/README.md", [title: "Math Demo", filename: "example-math-demo"]},
        {"examples/proof_pipeline/README.md",
         [title: "Proof Pipeline", filename: "example-proof-pipeline"]}
      ],
      groups_for_extras: [
        Introduction: ~w(readme changelog license),
        Guides: ~w(session-affinity),
        Examples: ~w(examples-overview example-math-demo example-proof-pipeline)
      ],
      groups_for_modules: [
        Core: [
          SnakeBridge,
          SnakeBridge.Runtime,
          SnakeBridge.Types,
          SnakeBridge.Config
        ],
        Generator: [
          SnakeBridge.Generator,
          SnakeBridge.Introspector,
          SnakeBridge.IntrospectionError,
          SnakeBridge.Scanner,
          SnakeBridge.Manifest,
          SnakeBridge.Lock,
          SnakeBridge.PythonEnv,
          SnakeBridge.EnvironmentError
        ]
      ]
    ]
  end

  defp package do
    [
      name: "snakebridge",
      files:
        ~w(lib priv/snakebridge priv/python .formatter.exs mix.exs README.md LICENSE CHANGELOG.md assets),
      exclude_patterns: [
        "priv/python/.pytest_cache",
        "priv/snakebridge/.pytest_cache",
        "priv/python/__pycache__",
        "priv/snakebridge/__pycache__",
        "priv/python/*.pyc",
        "priv/snakebridge/*.pyc",
        "priv/python/*.egg-info",
        "priv/snakebridge/*.egg-info",
        "priv/python/*.bak",
        "priv/snakebridge/*.bak"
        # "priv/plts",
        # "priv/data",
        # "docs/archive",
        # "priv/snakepit",
        # "priv/snakepit/*"
      ],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/snakebridge"
      }
    ]
  end

  defp aliases do
    []
  end
end
