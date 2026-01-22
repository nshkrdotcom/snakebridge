defmodule SnakeBridge.MixProject do
  use Mix.Project

  @version "0.12.1"
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
      canonical: "https://hexdocs.pm/snakebridge",
      assets: %{"assets" => "assets"},
      logo: "assets/snakebridge.svg",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      nest_modules_by_prefix: [SnakeBridge.Error]
    ]
  end

  defp extras do
    [
      # Getting Started
      {"README.md", [title: "Overview", filename: "readme"]},
      {"guides/GETTING_STARTED.md", title: "Installation"},

      # Guides
      {"guides/UNIVERSAL_FFI.md", title: "Universal FFI"},
      {"guides/GENERATED_WRAPPERS.md", title: "Generated Wrappers"},
      {"guides/TYPE_SYSTEM.md", title: "Type System"},
      {"guides/REFS_AND_SESSIONS.md", title: "References & Sessions"},
      {"guides/SESSION_AFFINITY.md", title: "Session Affinity"},
      {"guides/STREAMING.md", title: "Streaming"},
      {"guides/ERROR_HANDLING.md", title: "Error Handling"},
      {"guides/TELEMETRY.md", title: "Telemetry"},

      # How-To
      {"guides/CONFIGURATION.md", title: "Configuration"},
      {"guides/BEST_PRACTICES.md", title: "Best Practices"},
      {"guides/COVERAGE_REPORTS.md", title: "Coverage Reports"},

      # Examples
      {"examples/README.md", [title: "Examples", filename: "examples"]},
      {"examples/math_demo/README.md", [title: "Math Demo", filename: "example-math-demo"]},
      {"examples/proof_pipeline/README.md",
       [title: "Proof Pipeline", filename: "example-proof-pipeline"]},

      # About
      {"CHANGELOG.md", title: "Changelog"},
      {"LICENSE", title: "License"}
    ]
  end

  defp groups_for_extras do
    [
      "Getting Started": ~r/README|GETTING_STARTED/,
      Guides:
        ~r/guides\/(UNIVERSAL|GENERATED|TYPE_SYSTEM|REFS|SESSION_AFFINITY|STREAMING|ERROR|TELEMETRY)/,
      "How-To": ~r/guides\/(CONFIGURATION|BEST_PRACTICES|COVERAGE)/,
      Examples: ~r/examples\//,
      About: ~r/CHANGELOG|LICENSE/
    ]
  end

  defp groups_for_modules do
    [
      Core: [
        SnakeBridge,
        SnakeBridge.Runtime,
        SnakeBridge.Dynamic,
        SnakeBridge.Types
      ],
      Sessions: [
        SnakeBridge.SessionContext,
        SnakeBridge.SessionManager
      ],
      Configuration: [
        SnakeBridge.Config,
        SnakeBridge.ConfigHelper,
        SnakeBridge.Defaults
      ],
      "Code Generation": [
        SnakeBridge.Generator,
        SnakeBridge.Introspector,
        SnakeBridge.Scanner,
        SnakeBridge.Manifest,
        SnakeBridge.Lock,
        SnakeBridge.CoverageReport
      ],
      "Types & References": [
        SnakeBridge.Ref,
        SnakeBridge.StreamRef,
        SnakeBridge.Bytes,
        SnakeBridge.Types.Encoder,
        SnakeBridge.Types.Decoder
      ],
      Errors: [
        SnakeBridge.Error,
        SnakeBridge.ErrorTranslator,
        SnakeBridge.DynamicException
      ],
      Telemetry: [
        SnakeBridge.Telemetry
      ],
      Environment: [
        SnakeBridge.PythonEnv,
        SnakeBridge.EnvironmentError,
        SnakeBridge.IntrospectionError
      ]
    ]
  end

  defp package do
    [
      name: "snakebridge",
      files:
        ~w(lib priv/snakebridge priv/python .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      exclude_patterns: [
        # Python bytecode and cache directories
        ~r/__pycache__/,
        ~r/\.pyc$/,
        ~r/\.pytest_cache/,
        ~r/\.egg-info/,
        ~r/\.bak$/
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
