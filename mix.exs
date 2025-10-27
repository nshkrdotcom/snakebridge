defmodule SnakeBridge.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/nshkrdotcom/snakebridge"

  def project do
    [
      app: :snakebridge,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "SnakeBridge",
      description: "Configuration-driven Python library integration for Elixir",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {SnakeBridge.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies
      # Optional for now during dev
      {:snakepit, "~> 0.6", optional: true},
      # For config schemas
      {:ecto, "~> 3.11"},
      # JSON encoding
      {:jason, "~> 1.4"},

      # Development & Testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      # Property-based testing
      {:stream_data, "~> 1.0", only: :test},
      # Mocking
      {:mox, "~> 1.1", only: :test},
      # Runtime mocking
      {:mimic, "~> 1.7", only: :test},
      # OTP testing toolkit
      {:supertester, "~> 0.2.1", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "SnakeBridge",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/snakebridge.svg",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ["README.md"],
        "Release Notes": ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        Core: [
          SnakeBridge,
          SnakeBridge.Config,
          SnakeBridge.Generator,
          SnakeBridge.Runtime
        ],
        Discovery: [
          SnakeBridge.Discovery,
          SnakeBridge.Discovery.Introspector,
          SnakeBridge.Discovery.Parser
        ],
        Schema: [
          SnakeBridge.Schema,
          SnakeBridge.Schema.Descriptor,
          SnakeBridge.Schema.Validator,
          SnakeBridge.Schema.Differ
        ],
        "Type System": [
          SnakeBridge.TypeSystem,
          SnakeBridge.TypeSystem.Mapper,
          SnakeBridge.TypeSystem.Inference,
          SnakeBridge.TypeSystem.Validator
        ],
        "Developer Tools": [
          Mix.Tasks.Snakebridge.Discover,
          Mix.Tasks.Snakebridge.Validate,
          Mix.Tasks.Snakebridge.Diff,
          Mix.Tasks.Snakebridge.Generate,
          Mix.Tasks.Snakebridge.Clean
        ]
      ]
    ]
  end

  defp package do
    [
      name: "snakebridge",
      description: description(),
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md assets),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Online documentation" => "https://hexdocs.pm/snakebridge",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"]
    ]
  end

  defp description do
    """
    Configuration-driven Python library integration for Elixir. Automatically generate
    type-safe Elixir modules from declarative configs, enabling seamless integration with
    any Python library. Built on Snakepit for high-performance Python orchestration.
    """
  end

  defp aliases do
    [
      test: ["test --trace"],
      "test.watch": ["test.watch --stale"],
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end
end
