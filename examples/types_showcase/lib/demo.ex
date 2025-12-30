defmodule Demo do
  @moduledoc """
  Types Showcase - Demonstrates Python to Elixir Type Mapping.

  This demo shows how data types transform when crossing the Elixir-Python boundary.
  Each example displays:
    - The Elixir value being sent
    - The Python type it becomes
    - The value returned to Elixir
    - The Elixir type of the result

  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    Snakepit.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("""
      ======================================================================
                    SnakeBridge Types Showcase Demo
      ======================================================================

      This demo demonstrates how data types map between Elixir and Python.
      Each call shows the complete round-trip transformation:
        Elixir value -> gRPC -> Python -> gRPC -> Elixir value

      """)

      demo_integer()
      demo_float()
      demo_string()
      demo_list()
      demo_dict()
      demo_tuple()
      demo_none()
      demo_boolean()
      demo_bytes()
      demo_nested_structures()

      IO.puts("""

      ======================================================================
                           Demo Complete!
      ======================================================================

      Summary of Type Mappings:
        Python int      <-> Elixir integer
        Python float    <-> Elixir float
        Python str      <-> Elixir String (binary)
        Python list     <-> Elixir list
        Python dict     <-> Elixir map
        Python list     <-- Elixir tuple (convert with Tuple.to_list/1)
        Python None     <-> Elixir nil
        Python bool     <-> Elixir boolean
        Python bytes    <-> Elixir binary
        Nested structs  <-> Nested Elixir terms

      Try `iex -S mix` to experiment with more types!
      ======================================================================
      """)

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  # ==========================================================================
  # Type Demonstrations
  # ==========================================================================

  defp demo_integer do
    IO.puts("--- SECTION 1: Integer -------------------------------------------")
    IO.puts("")

    # Send an integer to Python and get its type
    value = 42

    type_call(
      description: "Integer type mapping",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [42])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: value,
      elixir_type: "integer"
    )

    # Also demonstrate with a larger integer
    large_value = 9_999_999_999_999_999_999

    type_call(
      description: "Large integer (arbitrary precision)",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [9999999999999999999])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: large_value,
      elixir_type: "integer"
    )

    IO.puts("")
  end

  defp demo_float do
    IO.puts("--- SECTION 2: Float ---------------------------------------------")
    IO.puts("")

    value = 3.14159

    type_call(
      description: "Float type mapping",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [3.14159])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: value,
      elixir_type: "float"
    )

    # Scientific notation
    sci_value = 1.23e-10

    type_call(
      description: "Float with scientific notation",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [1.23e-10])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: sci_value,
      elixir_type: "float"
    )

    IO.puts("")
  end

  defp demo_string do
    IO.puts("--- SECTION 3: String --------------------------------------------")
    IO.puts("")

    value = "Hello, SnakeBridge!"

    type_call(
      description: "String type mapping",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [\"Hello, SnakeBridge!\"])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: value,
      elixir_type: "binary (String)"
    )

    # Unicode string
    unicode_value = "Hello"

    type_call(
      description: "Unicode string with emoji",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [\"Hello\"])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: unicode_value,
      elixir_type: "binary (String)"
    )

    IO.puts("")
  end

  defp demo_list do
    IO.puts("--- SECTION 4: List ----------------------------------------------")
    IO.puts("")

    value = [1, 2, 3, 4, 5]

    type_call(
      description: "List type mapping",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [[1, 2, 3, 4, 5]])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: value,
      elixir_type: "list"
    )

    # Mixed type list
    mixed_value = [1, "two", 3.0, true]

    type_call(
      description: "Mixed-type list",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [[1, \"two\", 3.0, true]])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: mixed_value,
      elixir_type: "list"
    )

    IO.puts("")
  end

  defp demo_dict do
    IO.puts("--- SECTION 5: Dict/Map ------------------------------------------")
    IO.puts("")

    value = %{"name" => "Alice", "age" => 30}

    type_call(
      description: "Dict/Map type mapping",
      elixir_call:
        "Snakepit.call(\"builtins\", \"type\", [%{\"name\" => \"Alice\", \"age\" => 30}])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: value,
      elixir_type: "map"
    )

    # Nested map
    nested_value = %{"user" => %{"name" => "Bob", "scores" => [95, 87, 92]}}

    type_call(
      description: "Nested dict/map",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [%{\"user\" => %{...}}])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: nested_value,
      elixir_type: "map"
    )

    IO.puts("")
  end

  defp demo_tuple do
    IO.puts("--- SECTION 6: Tuple (as List) -----------------------------------")
    IO.puts("")

    # Note: Elixir tuples must be converted to lists for JSON serialization
    # The gRPC bridge uses JSON, which doesn't have a native tuple type
    tuple_value = {1, 2, 3}
    list_value = Tuple.to_list(tuple_value)

    IO.puts("    Note: Elixir tuples must be converted to lists for gRPC/JSON transport.")
    IO.puts("          Use Tuple.to_list/1 before sending, tuple() in Python if needed.")
    IO.puts("")

    type_call(
      description: "Tuple converted to list",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [Tuple.to_list({1, 2, 3})])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: list_value,
      elixir_type: "list (from tuple)"
    )

    IO.puts("")
  end

  defp demo_none do
    IO.puts("--- SECTION 7: None/nil ------------------------------------------")
    IO.puts("")

    value = nil

    type_call(
      description: "None/nil type mapping",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [nil])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: value,
      elixir_type: "nil (atom)"
    )

    IO.puts("")
  end

  defp demo_boolean do
    IO.puts("--- SECTION 8: Boolean -------------------------------------------")
    IO.puts("")

    true_value = true

    type_call(
      description: "Boolean true",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [true])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: true_value,
      elixir_type: "boolean (atom)"
    )

    false_value = false

    type_call(
      description: "Boolean false",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [false])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: false_value,
      elixir_type: "boolean (atom)"
    )

    IO.puts("")
  end

  defp demo_bytes do
    IO.puts("--- SECTION 9: Bytes/Binary --------------------------------------")
    IO.puts("")

    # Raw binary data
    value = <<0x48, 0x65, 0x6C, 0x6C, 0x6F>>

    type_call(
      description: "Bytes/Binary type mapping",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [<<72, 101, 108, 108, 111>>])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: value,
      elixir_type: "binary"
    )

    IO.puts("")
  end

  defp demo_nested_structures do
    IO.puts("--- SECTION 10: Complex Nested Structures ------------------------")
    IO.puts("")

    # Complex nested structure
    value = %{
      "metadata" => %{
        "version" => "1.0",
        "count" => 3
      },
      "items" => [
        %{"id" => 1, "name" => "first", "active" => true},
        %{"id" => 2, "name" => "second", "active" => false},
        %{"id" => 3, "name" => "third", "active" => true}
      ],
      "tags" => ["elixir", "python", "interop"]
    }

    type_call(
      description: "Complex nested structure",
      elixir_call: "Snakepit.call(\"builtins\", \"type\", [%{...complex...}])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: value,
      elixir_type: "map (with nested lists and maps)"
    )

    # Demonstrate accessing nested data via Python
    IO.puts("    Additional: Demonstrate round-trip of nested data")
    IO.puts("")

    identity_call(
      description: "Round-trip nested structure via json.loads(json.dumps(...))",
      elixir_value: value
    )

    IO.puts("")
  end

  # ==========================================================================
  # Helper Functions
  # ==========================================================================

  defp type_call(opts) do
    IO.puts("    +-- #{opts[:description]}")
    IO.puts("    |")
    IO.puts("    |  Elixir call:     #{opts[:elixir_call]}")
    IO.puts("    |  ------------------------------------------------")
    IO.puts("    |  Python module:   #{opts[:python_module]}")
    IO.puts("    |  Python function: #{opts[:python_function]}")
    IO.puts("    |  Arguments:       [#{format_value(opts[:elixir_value])}]")
    IO.puts("    |")

    # Make the actual call to get Python type
    start_time = System.monotonic_time(:microsecond)

    result =
      case snakepit_call(opts[:python_module], opts[:python_function], [opts[:elixir_value]]) do
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end

    elapsed = System.monotonic_time(:microsecond) - start_time

    case result do
      {:ok, python_type} ->
        IO.puts("    |  Python type:     #{format_python_type(python_type)}")
        IO.puts("    |  Elixir type:     #{opts[:elixir_type]}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:ok, #{inspect(python_type)}} (#{elapsed} us)")

      {:error, reason} ->
        IO.puts("    |  Error:           #{inspect(reason)}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:error, #{inspect(reason)}} (#{elapsed} us)")
    end

    IO.puts("")
    result
  end

  defp identity_call(opts) do
    IO.puts("    +-- #{opts[:description]}")
    IO.puts("    |")
    IO.puts("    |  Sending:         #{format_value(opts[:elixir_value])}")
    IO.puts("    |")

    # Round-trip through JSON to verify structure preservation
    start_time = System.monotonic_time(:microsecond)

    result =
      with {:ok, json_str} <- snakepit_call("json", "dumps", [opts[:elixir_value]]),
           {:ok, parsed} <- snakepit_call("json", "loads", [json_str]) do
        {:ok, parsed}
      end

    elapsed = System.monotonic_time(:microsecond) - start_time

    case result do
      {:ok, value} ->
        IO.puts("    |  Received:        #{format_value(value)}")
        IO.puts("    |  Match:           #{opts[:elixir_value] == value}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:ok, <data>} (#{elapsed} us)")

      {:error, reason} ->
        IO.puts("    |  Error:           #{inspect(reason)}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:error, #{inspect(reason)}} (#{elapsed} us)")
    end

    IO.puts("")
    result
  end

  defp format_value(value) when is_binary(value) do
    if String.printable?(value) do
      inspect(value, limit: 50, printable_limit: 100)
    else
      "<<#{byte_size(value)} bytes>>"
    end
  end

  defp format_value(value) when is_map(value) and map_size(value) > 3 do
    "%{...#{map_size(value)} keys...}"
  end

  defp format_value(value) when is_list(value) and length(value) > 5 do
    "[...#{length(value)} items...]"
  end

  defp format_value(value) do
    inspect(value, limit: 50, printable_limit: 100)
  end

  defp format_python_type(type_str) when is_binary(type_str) do
    # Python type() returns strings like "<class 'int'>"
    type_str
  end

  defp format_python_type(other) do
    inspect(other)
  end

  # Helper to call Python via Snakepit with proper payload format
  defp snakepit_call(python_module, python_function, args) do
    payload =
      SnakeBridge.Runtime.protocol_payload()
      |> Map.merge(%{
        "library" => python_module |> String.split(".") |> List.first(),
        "python_module" => python_module,
        "function" => python_function,
        "args" => args,
        "kwargs" => %{},
        "idempotent" => false
      })

    case Snakepit.execute("snakebridge.call", payload) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Examples.record_failure()
        {:error, reason}

      other ->
        {:ok, other}
    end
  end
end
