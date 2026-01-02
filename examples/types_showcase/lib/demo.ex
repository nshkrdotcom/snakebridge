defmodule Demo do
  @moduledoc """
  Types Showcase - Demonstrates Python to Elixir Type Mapping.

  This demo shows how data types transform when crossing the Elixir-Python boundary.
  Each example displays:
    - The Elixir value being sent
    - The Python type it becomes
    - The value returned to Elixir
    - The Elixir type of the result

  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    SnakeBridge.run_as_script(fn ->
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
      demo_atoms_and_refs()

      # New v0.8.4 type features
      demo_explicit_bytes()
      demo_non_string_key_maps()

      IO.puts("""

      ======================================================================
                           Demo Complete!
      ======================================================================

      Summary of Type Mappings:
        Python int      <-> Elixir integer
        Python float    <-> Elixir float
        Python str      <-> Elixir String (binary)
        Python list     <-> Elixir list
        Python dict     <-> Elixir map (string keys)
        Python dict     <-> Elixir map (tagged dict for non-string keys) [v0.8.4]
        Python tuple    <-> Elixir tuple
        Python None     <-> Elixir nil
        Python bool     <-> Elixir boolean
        Python bytes    <-> Elixir binary
        Python bytes    <-  SnakeBridge.bytes(binary) [v0.8.4 explicit]
        Nested structs  <-> Nested Elixir terms
        Python str      <-  Elixir atom (default)
        Python object   <-> Elixir ref handle

      New in v0.8.4:
        - Use SnakeBridge.bytes/1 for explicit bytes encoding
        - Maps with integer/tuple keys now round-trip correctly

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

  defp demo_atoms_and_refs do
    IO.puts("--- SECTION 11: Atoms and Auto-Refs ------------------------------")
    IO.puts("")

    type_call(
      description: "Atom passed as Python string",
      elixir_call: "SnakeBridge.call(%{python_module: \"builtins\"}, \"type\", [:cuda])",
      python_module: "builtins",
      python_function: "type",
      elixir_value: :cuda,
      elixir_type: "atom (encoded as Python str)"
    )

    IO.puts("    +-- Auto-ref for complex objects and method chaining")
    IO.puts("    |")

    IO.puts(
      "    |  Elixir call:     SnakeBridge.call(%{python_module: \"pathlib\"}, \"Path\", [\"/tmp\"])"
    )

    IO.puts("    |")

    case snakepit_call("pathlib", "Path", ["/tmp"]) do
      {:ok, %SnakeBridge.Ref{} = ref} ->
        IO.puts("    |  Ref type:       SnakeBridge.Ref")
        handle_pathlib_chain(ref)

      {:ok, %{"__type__" => "ref"} = ref} ->
        IO.puts("    |  Ref type:       #{inspect(ref["__type__"])}")
        handle_pathlib_chain(ref)

      {:ok, other} ->
        Examples.record_failure()
        IO.puts("    |  Error:          Unexpected value: #{inspect(other)}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:error, unexpected_result}")

      {:error, reason} ->
        IO.puts("    |  Error:          #{inspect(reason)}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:error, #{inspect(reason)}}")
    end

    IO.puts("")
  end

  # ==========================================================================
  # New v0.8.4 Type Features
  # ==========================================================================

  defp demo_explicit_bytes do
    IO.puts("--- SECTION 12: SnakeBridge.Bytes (NEW in v0.8.4) ----------------")
    IO.puts("")

    IO.puts("    Use SnakeBridge.bytes/1 when Python expects bytes, not str.")
    IO.puts("    Essential for: hashlib, base64, struct, cryptography, etc.")
    IO.puts("")

    # Hashlib requires bytes
    IO.puts("    +-- hashlib.md5 with bytes wrapper")
    IO.puts("    |")

    IO.puts(
      "    |  Elixir call:     SnakeBridge.call(\"hashlib\", \"md5\", [SnakeBridge.bytes(\"abc\")])"
    )

    IO.puts("    |")

    case SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")]) do
      {:ok, hash_ref} ->
        case SnakeBridge.method(hash_ref, "hexdigest", []) do
          {:ok, hex} ->
            IO.puts("    |  Python hash:    #{hex}")
            expected = "900150983cd24fb0d6963f7d28e17f72"
            IO.puts("    |  Expected:       #{expected}")
            IO.puts("    |  Match:          #{hex == expected}")
            IO.puts("    |")
            IO.puts("    +-- Result: {:ok, #{inspect(hex)}}")

          {:error, reason} ->
            Examples.record_failure()
            IO.puts("    |  Error:          #{inspect(reason)}")
            IO.puts("    +-- Result: {:error, ...}")
        end

      {:error, reason} ->
        Examples.record_failure()
        IO.puts("    |  Error:          #{inspect(reason)}")
        IO.puts("    +-- Result: {:error, ...}")
    end

    IO.puts("")

    # Base64 round-trip
    IO.puts("    +-- base64 binary round-trip")
    IO.puts("    |")
    original = <<0, 1, 2, 128, 255>>
    IO.puts("    |  Original binary: #{inspect(original)}")

    case SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)]) do
      {:ok, encoded} ->
        IO.puts("    |  Base64 encoded: #{inspect(encoded)}")

        case SnakeBridge.call("base64", "b64decode", [encoded]) do
          {:ok, decoded} ->
            IO.puts("    |  Decoded:        #{inspect(decoded)}")
            IO.puts("    |  Round-trip OK:  #{original == decoded}")
            IO.puts("    +-- Result: {:ok, round-trip successful}")

          {:error, reason} ->
            Examples.record_failure()
            IO.puts("    |  Decode error:   #{inspect(reason)}")
            IO.puts("    +-- Result: {:error, ...}")
        end

      {:error, reason} ->
        Examples.record_failure()
        IO.puts("    |  Encode error:   #{inspect(reason)}")
        IO.puts("    +-- Result: {:error, ...}")
    end

    IO.puts("")
  end

  defp demo_non_string_key_maps do
    IO.puts("--- SECTION 13: Non-String Key Maps (NEW in v0.8.4) --------------")
    IO.puts("")

    IO.puts("    Maps with integer, tuple, or atom keys now serialize correctly")
    IO.puts("    using the tagged dict wire format.")
    IO.puts("")

    # Integer keys
    IO.puts("    +-- Integer key map")
    IO.puts("    |")
    int_map = %{1 => "one", 2 => "two", 3 => "three"}
    IO.puts("    |  Elixir map:     #{inspect(int_map)}")

    case SnakeBridge.call("builtins", "dict", [int_map]) do
      {:ok, returned} when is_map(returned) and not is_struct(returned) ->
        # Dict was returned directly (JSON-serializable)
        # Verify integer keys are preserved
        value = Map.get(returned, 2)
        IO.puts("    |  Returned:       #{inspect(returned)}")
        IO.puts("    |  map[2]:         #{inspect(value)}")
        IO.puts("    |  Key is integer: #{value == "two"}")
        IO.puts("    +-- Result: {:ok, integer keys preserved}")

      {:ok, ref} when is_struct(ref) ->
        # Returned as ref - call method on it
        case SnakeBridge.method(ref, "get", [2]) do
          {:ok, value} ->
            IO.puts("    |  dict.get(2):    #{inspect(value)}")
            IO.puts("    |  Key is integer: #{value == "two"}")
            IO.puts("    +-- Result: {:ok, integer keys preserved}")

          {:error, reason} ->
            Examples.record_failure()
            IO.puts("    |  Error:          #{inspect(reason)}")
            IO.puts("    +-- Result: {:error, ...}")
        end

      {:error, reason} ->
        Examples.record_failure()
        IO.puts("    |  Error:          #{inspect(reason)}")
        IO.puts("    +-- Result: {:error, ...}")
    end

    IO.puts("")

    # Tuple keys (coordinate map)
    IO.puts("    +-- Tuple key map (coordinate example)")
    IO.puts("    |")
    coord_map = %{{0, 0} => "origin", {1, 0} => "x-axis", {0, 1} => "y-axis"}
    IO.puts("    |  Elixir map:     #{inspect(coord_map)}")

    case SnakeBridge.call("builtins", "dict", [coord_map]) do
      {:ok, returned} when is_map(returned) and not is_struct(returned) ->
        # Dict was returned directly (JSON-serializable)
        # Verify tuple keys are preserved
        value = Map.get(returned, {0, 0})
        IO.puts("    |  Returned:       #{inspect(returned)}")
        IO.puts("    |  map[(0,0)]:     #{inspect(value)}")
        IO.puts("    |  Tuple key OK:   #{value == "origin"}")
        IO.puts("    +-- Result: {:ok, tuple keys preserved}")

      {:ok, ref} when is_struct(ref) ->
        # Returned as ref - call method on it
        case SnakeBridge.method(ref, "get", [{0, 0}]) do
          {:ok, value} ->
            IO.puts("    |  dict[(0,0)]:    #{inspect(value)}")
            IO.puts("    |  Tuple key OK:   #{value == "origin"}")
            IO.puts("    +-- Result: {:ok, tuple keys preserved}")

          {:error, reason} ->
            Examples.record_failure()
            IO.puts("    |  Error:          #{inspect(reason)}")
            IO.puts("    +-- Result: {:error, ...}")
        end

      {:error, reason} ->
        Examples.record_failure()
        IO.puts("    |  Error:          #{inspect(reason)}")
        IO.puts("    +-- Result: {:error, ...}")
    end

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
      {:ok, %SnakeBridge.Ref{} = ref} ->
        case python_repr(ref) do
          {:ok, repr} ->
            IO.puts("    |  Python type:     #{format_python_type(repr)}")
            IO.puts("    |  Elixir type:     #{opts[:elixir_type]}")
            IO.puts("    |")
            IO.puts("    +-- Result: {:ok, #{inspect(repr)}} (#{elapsed} us)")

          {:error, reason} ->
            Examples.record_failure()
            IO.puts("    |  Error:           #{inspect(reason)}")
            IO.puts("    |")
            IO.puts("    +-- Result: {:error, #{inspect(reason)}} (#{elapsed} us)")
        end

      {:ok, %{"__type__" => "ref"} = ref} ->
        case python_repr(ref) do
          {:ok, repr} ->
            IO.puts("    |  Python type:     #{format_python_type(repr)}")
            IO.puts("    |  Elixir type:     #{opts[:elixir_type]}")
            IO.puts("    |")
            IO.puts("    +-- Result: {:ok, #{inspect(repr)}} (#{elapsed} us)")

          {:error, reason} ->
            Examples.record_failure()
            IO.puts("    |  Error:           #{inspect(reason)}")
            IO.puts("    |")
            IO.puts("    +-- Result: {:error, #{inspect(reason)}} (#{elapsed} us)")
        end

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

  defp python_repr(ref) do
    SnakeBridge.Runtime.call_dynamic("builtins", "repr", [ref])
  end

  defp handle_pathlib_chain(ref) do
    case SnakeBridge.Runtime.call_method(ref, :joinpath, ["snakebridge.txt"]) do
      {:ok, %SnakeBridge.Ref{} = next_ref} ->
        handle_pathlib_result(next_ref)

      {:ok, %{"__type__" => "ref"} = next_ref} ->
        handle_pathlib_result(next_ref)

      {:error, reason} ->
        Examples.record_failure()
        IO.puts("    |  Error:          #{inspect(reason)}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:error, #{inspect(reason)}}")

      other ->
        Examples.record_failure()
        IO.puts("    |  Error:          #{inspect(other)}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:error, #{inspect(other)}}")
    end
  end

  defp handle_pathlib_result(ref) do
    case SnakeBridge.Runtime.call_method(ref, :as_posix, []) do
      {:ok, path} ->
        IO.puts("    |  Chained result: #{format_value(path)}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:ok, #{inspect(path)}}")

      {:error, reason} ->
        Examples.record_failure()
        IO.puts("    |  Error:          #{inspect(reason)}")
        IO.puts("    |")
        IO.puts("    +-- Result: {:error, #{inspect(reason)}}")
    end
  end

  # Helper to call Python via SnakeBridge runtime
  # Uses string module path directly (v0.8.4+ Universal FFI)
  defp snakepit_call(python_module, python_function, args) do
    case SnakeBridge.Runtime.call(python_module, python_function, args) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Examples.record_failure()
        {:error, reason}
    end
  end
end
