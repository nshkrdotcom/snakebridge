defmodule SnakeBridge.MixProject do
  use Mix.Project

  @version "0.9.0"
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
      {:snakepit, "~> 0.11.0"},

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
      extras: extras(),
      groups_for_extras: [
        # Introduction
        Introduction: ~w(readme getting-started),

        # Core Concepts - Essential knowledge for using SnakeBridge
        "Core Concepts": ~w(universal-ffi generated-wrappers type-system),

        # Sessions & State - Managing Python state and object lifecycles
        "Sessions & State": ~w(refs-and-sessions session-affinity),

        # Advanced Features - Streaming, errors, and observability
        "Advanced Features": ~w(streaming error-handling telemetry),

        # Best Practices
        "Best Practices": ~w(best-practices),

        # Examples
        Examples: ~w(examples-overview example-math-demo example-proof-pipeline),

        # Reference
        Reference: ~w(changelog license)
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

  defp extras do
    [
      # Introduction
      "README.md",
      {"guides/GETTING_STARTED.md", [title: "Getting Started", filename: "getting-started"]},

      # Core Concepts
      {"guides/UNIVERSAL_FFI.md", [title: "Universal FFI", filename: "universal-ffi"]},
      {"guides/GENERATED_WRAPPERS.md",
       [title: "Generated Wrappers", filename: "generated-wrappers"]},
      {"guides/TYPE_SYSTEM.md", [title: "Type System", filename: "type-system"]},

      # Sessions & State
      {"guides/REFS_AND_SESSIONS.md",
       [title: "Refs and Sessions", filename: "refs-and-sessions"]},
      {"guides/SESSION_AFFINITY.md", [title: "Session Affinity", filename: "session-affinity"]},

      # Advanced Features
      {"guides/STREAMING.md", [title: "Streaming", filename: "streaming"]},
      {"guides/ERROR_HANDLING.md", [title: "Error Handling", filename: "error-handling"]},
      {"guides/TELEMETRY.md", [title: "Telemetry", filename: "telemetry"]},

      # Best Practices
      {"guides/BEST_PRACTICES.md", [title: "Best Practices", filename: "best-practices"]},

      # Examples
      {"examples/README.md", [title: "Examples Overview", filename: "examples-overview"]},
      {"examples/math_demo/README.md", [title: "Math Demo", filename: "example-math-demo"]},
      {"examples/proof_pipeline/README.md",
       [title: "Proof Pipeline", filename: "example-proof-pipeline"]},

      # Reference
      "CHANGELOG.md",
      "LICENSE"
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
