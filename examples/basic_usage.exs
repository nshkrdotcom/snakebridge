#!/usr/bin/env elixir

# SnakeBridge Basic Usage Demo
#
# This script demonstrates how to use the Mix task to generate adapters
# and how to use SnakeBridge.Runtime directly.
#
# Usage:
#   elixir examples/basic_usage.exs

IO.puts("""
=== SnakeBridge v2 Basic Usage ===

SnakeBridge provides two ways to call Python from Elixir:

1. GENERATED ADAPTERS (Recommended)
   Generate type-safe Elixir modules from Python libraries.

2. DIRECT RUNTIME CALLS
   Call Python functions directly at runtime.


--- 1. Generating Adapters ---

Use the Mix task to generate an adapter:

    $ mix snakebridge.gen json

This creates lib/snakebridge/adapters/json.ex with:
- Type-safe function wrappers
- Full @spec declarations
- Documentation from Python docstrings

Example generated code:

    defmodule SnakeBridge.Json do
      @moduledoc "Python module: json"
      use SnakeBridge.Adapter

      @doc "Serialize obj to a JSON formatted str."
      @spec dumps(any(), keyword()) :: String.t()
      def dumps(obj, opts \\\\ []) do
        __python_call__("dumps", [obj, opts])
      end

      @doc "Deserialize s to a Python object."
      @spec loads(String.t()) :: any()
      def loads(s) do
        __python_call__("loads", [s])
      end
    end


--- 2. Direct Runtime Calls ---

For one-off calls or experimentation, use SnakeBridge.Runtime:

    alias SnakeBridge.Runtime

    # Call a Python function directly
    {:ok, result} = Runtime.call("math", "sqrt", %{x: 16})
    # result = 4.0

    # With timeout option
    {:ok, data} = Runtime.call("json", "loads", %{s: ~s({"key": "value"})}, timeout: 5000)
    # data = %{"key" => "value"}

    # Streaming results
    Runtime.stream("mymodule", "generate_items", %{count: 100})
    |> Stream.each(&IO.inspect/1)
    |> Stream.run()


--- Type Mapping ---

SnakeBridge automatically converts between Python and Elixir types:

    Python          Elixir
    ------          ------
    None       <->  nil
    bool       <->  true/false
    int        <->  integer
    float      <->  float
    str        <->  String.t()
    list       <->  list()
    dict       <->  map()
    tuple      <->  tuple (tagged)
    set        <->  MapSet.t() (tagged)
    datetime   <->  DateTime.t() (tagged)
    bytes      <->  binary (base64 tagged)
    inf        <->  :infinity
    -inf       <->  :neg_infinity
    nan        <->  :nan


--- Getting Started ---

1. Install snakebridge in your mix.exs:

    {:snakebridge, "~> 2.0"}

2. Generate an adapter for your Python library:

    $ mix snakebridge.gen numpy

3. Use the generated module in your code:

    alias SnakeBridge.Numpy

    {:ok, arr} = Numpy.array([1, 2, 3, 4, 5])
    {:ok, mean} = Numpy.mean(arr)

For more examples, see:
  - examples/generator_demo.exs - Full generator workflow
  - examples/types_demo.exs - Type encoding/decoding

""")
