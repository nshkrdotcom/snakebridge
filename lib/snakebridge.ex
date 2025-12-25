defmodule SnakeBridge do
  @moduledoc """
  SnakeBridge - Python library integration for Elixir.

  SnakeBridge generates type-safe Elixir adapters for Python libraries with full
  IDE support, documentation, and type specs.

  ## Quick Start (Recommended)

  1. Add SnakeBridge to your compilers in `mix.exs`:

      def project do
        [
          compilers: [:snakebridge] ++ Mix.compilers(),
          # ...
        ]
      end

  2. Configure the Python libraries you need in `config/config.exs`:

      config :snakebridge,
        adapters: [:json, :numpy, :sympy]

  3. Run `mix compile` - adapters are generated automatically:

      $ mix compile
      SnakeBridge: Generating json adapter...
        Generated 4 functions, 3 classes
      SnakeBridge: Generating numpy adapter...
        Generated 56 functions, 0 classes

  4. Use the generated modules:

      iex> Json.dumps(%{"hello" => "world"}, false, true, true, true, nil, nil, nil, nil, nil, false)
      {:ok, "{\\"hello\\": \\"world\\"}"}

      iex> Json.__functions__()
      [{:dump, 12, Json, "Serialize obj..."}, ...]

      iex> Json.__search__("decode")
      [{:loads, 8, Json, "Deserialize..."}, ...]

  ## How It Works

  The SnakeBridge compiler:

  1. Reads your `config :snakebridge, adapters: [...]` configuration
  2. Introspects each Python library to discover functions, classes, and types
  3. Generates Elixir modules with `@doc`, `@spec`, and full IDE support
  4. Outputs to `lib/snakebridge_generated/` (auto-gitignored)

  Generated code is ephemeral - it's regenerated on `mix compile` and excluded
  from git via an auto-created `.gitignore`. Your repo stays clean.

  ## Generated Module Features

  Each generated module provides:

  - **Functions** - All public Python functions as Elixir functions
  - **Documentation** - Python docstrings converted to `@doc`
  - **Type Specs** - `@spec` for Dialyzer and IDE support
  - **Discovery** - `__functions__/0`, `__classes__/0`, `__search__/1`

  Example:

      # Discover available functions
      iex> Numpy.__functions__() |> Enum.take(3)
      [
        {:abs, 1, Numpy, "Absolute value..."},
        {:add, 2, Numpy, "Add two arrays..."},
        {:arange, 3, Numpy, "Return evenly spaced values..."}
      ]

      # Search for functions
      iex> Numpy.__search__("matrix")
      [{:matmul, 2, Numpy, "Matrix multiplication..."}, ...]

      # Get help
      iex> h Numpy.array

  ## Manual Generation

  For cases where you want to commit generated code (not recommended):

      $ mix snakebridge.gen json
      $ mix snakebridge.gen numpy --output lib/my_adapters/

  See `mix help snakebridge.gen` for options.

  ## Type System

  SnakeBridge handles type conversion between Elixir and Python:

  - **Primitives**: integers, floats, strings, booleans, nil
  - **Collections**: lists, maps, tuples (tagged), sets (MapSet)
  - **Special**: DateTime, Date, Time, binaries, infinity, NaN

  See `SnakeBridge.Types.Encoder` and `SnakeBridge.Types.Decoder`.

  ## Direct Runtime Calls

  For ad-hoc Python calls without generated modules:

      {:ok, result} = SnakeBridge.call("json", "dumps", %{obj: %{key: "value"}})

  ## Configuration

      config :snakebridge,
        # Python libraries to generate adapters for
        adapters: [:json, :numpy, :sympy],

        # Or with options
        adapters: [
          :json,
          {:numpy, functions: ["array", "zeros", "ones"]},
          {:sympy, exclude: ["init_printing"]}
        ]

  ## Mix Tasks

  - `mix snakebridge.gen <library>` - Manually generate an adapter
  - `mix snakebridge.list` - List generated adapters
  - `mix snakebridge.info <library>` - Show adapter details
  - `mix snakebridge.clean <library>` - Remove an adapter

  ## Requirements

  - Python 3.7+ in PATH
  - Target Python libraries must be installed (`pip install numpy`)
  """

  # Delegate core runtime functions
  defdelegate call(module, function, args \\ %{}, opts \\ []), to: SnakeBridge.Runtime
  defdelegate stream(module, function, args \\ %{}, callback, opts \\ []), to: SnakeBridge.Runtime

  @doc """
  Returns the version of SnakeBridge.

  ## Examples

      iex> SnakeBridge.version()
      "0.4.0"

  """
  @spec version() :: String.t()
  def version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end
end
