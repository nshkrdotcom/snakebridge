defmodule SnakeBridge do
  @moduledoc """
  SnakeBridge - Manifest-driven Python library integration for Elixir.

  SnakeBridge provides a declarative, type-safe way to integrate Python libraries
  into Elixir applications. It uses JSON manifests to define Python function
  signatures and automatically generates Elixir modules with proper documentation
  and type specs.

  ## Quick Start

  Use built-in adapters immediately - no configuration needed:

      # SymPy for symbolic mathematics
      {:ok, roots} = SnakeBridge.SymPy.solve(%{expr: "x**2 - 1", symbol: "x"})

      # PyLatexEnc for LaTeX parsing
      {:ok, nodes} = SnakeBridge.PyLatexEnc.parse(%{latex: "\\\\frac{1}{2}"})

  ## Direct Runtime Calls

  For ad-hoc Python function calls without generated modules:

      # Call any Python function
      {:ok, result} = SnakeBridge.call("json", "dumps", %{obj: %{hello: "world"}})

      # With streaming
      SnakeBridge.stream("requests", "iter_content", %{url: "..."}, fn chunk ->
        IO.inspect(chunk, label: "Chunk")
      end)

  ## Architecture

  SnakeBridge consists of three main layers:

  1. **Generation Layer** - Introspects Python libraries and generates Elixir modules
  2. **Type System** - Handles lossless conversion between Elixir and Python types
  3. **Runtime Layer** - Executes Python code through Snakepit's gRPC interface

  ### Type System

  SnakeBridge automatically handles type conversion between Elixir and Python:

  - Primitives: integers, floats, strings, booleans, nil
  - Collections: lists, maps, tuples, sets
  - Special types: DateTime, Date, Time, binaries
  - Tagged types for lossless round-tripping

  See `SnakeBridge.Types.Encoder` and `SnakeBridge.Types.Decoder` for details.

  ### Generated Modules

  Generated modules live in `lib/snakebridge/adapters/` and provide:

  - Full function documentation from Python docstrings
  - Type specs inferred from Python type hints
  - Dialyzer-compatible types
  - IDE autocomplete support

  ## Manifest Format

  Manifests are JSON files that describe Python libraries:

      {
        "name": "numpy",
        "python_module": "numpy",
        "elixir_module": "SnakeBridge.NumPy",
        "functions": [
          {
            "name": "array",
            "args": ["object"],
            "returns": {"type": "ndarray"}
          }
        ]
      }

  ## Mix Tasks

  - `mix snakebridge.gen <library>` - Generate adapter for a Python library
  - `mix snakebridge.discover <module>` - Discover available functions
  - `mix snakebridge.validate <manifest>` - Validate manifest file

  ## Configuration

  Configure in `config/config.exs`:

      config :snakebridge,
        # Auto-start Snakepit on first call (default: true)
        auto_start_snakepit: true,

        # Custom manifest directories
        custom_manifests: ["priv/my_manifests/**/*.json"]

      # Configure Snakepit pool settings
      config :snakepit,
        pooling_enabled: true,
        pool_size: 4,
        adapter_module: Snakepit.Adapters.GrpcAdapter

  ## Examples

      # Using generated adapters
      alias SnakeBridge.NumPy

      {:ok, arr} = NumPy.array(%{object: [1, 2, 3, 4]})
      {:ok, result} = NumPy.sum(%{array: arr})

      # Direct runtime calls
      {:ok, json_str} = SnakeBridge.call("json", "dumps", %{
        obj: %{name: "Alice", age: 30}
      })

      # Streaming data
      SnakeBridge.stream("requests", "get", %{url: "https://api.example.com/stream"},
        fn chunk ->
          process_chunk(chunk)
        end,
        timeout: 60_000
      )

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, reason}` tuples:

      case SnakeBridge.call("math", "sqrt", %{x: -1}) do
        {:ok, result} ->
          IO.puts("Result: \#{result}")

        {:error, %{category: :python_error, message: msg}} ->
          IO.puts("Python error: \#{msg}")

        {:error, reason} ->
          IO.puts("Error: \#{inspect(reason)}")
      end

  ## Telemetry

  SnakeBridge emits telemetry events for monitoring and observability:

  - `[:snakebridge, :runtime, :call]` - Runtime function calls
  - `[:snakebridge, :runtime, :stream]` - Streaming calls

  Measurements include:
  - `duration` - Call duration in native time units

  Metadata includes:
  - `module` - Python module name
  - `function` - Function name
  - `success` - Boolean indicating success/failure

  Example handler:

      :telemetry.attach(
        "snakebridge-handler",
        [:snakebridge, :runtime, :call],
        fn _event, measurements, metadata, _config ->
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
          IO.puts("Call \#{metadata.module}.\#{metadata.function} took \#{duration_ms}ms")
        end,
        nil
      )

  ## See Also

  - `SnakeBridge.Runtime` - Core runtime execution
  - `SnakeBridge.Types.Encoder` - Elixir to Python encoding
  - `SnakeBridge.Types.Decoder` - Python to Elixir decoding
  - [Snakepit](https://hex.pm/packages/snakepit) - Underlying Python orchestration
  """

  # Delegate core runtime functions
  defdelegate call(module, function, args \\ %{}, opts \\ []), to: SnakeBridge.Runtime
  defdelegate stream(module, function, args \\ %{}, callback, opts \\ []), to: SnakeBridge.Runtime

  @doc """
  Returns the version of SnakeBridge.

  ## Examples

      iex> SnakeBridge.version()
      "0.3.2"

  """
  @spec version() :: String.t()
  def version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end
end
