# Fix #5: Encoder Fallback Error

**Status**: Specification
**Priority**: Medium
**Complexity**: Low
**Estimated Changes**: ~50 lines Elixir

## Problem Statement

`Types.Encoder.encode/1` ends with:

```elixir
def encode(other) do
  inspect(other)
end
```

This creates a false sense of "it works" while actually:

1. **Sending arbitrary inspected strings** into Python
2. **Producing inconsistent results** across Elixir versions/inspect settings
3. **Masking serialization bugs** until deep inside Python code

**Example failure modes**:

```elixir
# PID gets inspected
SnakeBridge.call("lib", "fn", [self()])
# => Python receives "#PID<0.123.0>" string, not a process reference

# Port gets inspected
SnakeBridge.call("lib", "fn", [some_port])
# => Python receives "#Port<0.5>" string

# Custom struct without encoder
SnakeBridge.call("lib", "fn", [%MyStruct{field: "value"}])
# => Python receives "%MyStruct{field: \"value\"}" string
```

Universal FFI needs **predictable failure modes** and **predictable conversions**.

## Solution

Replace the fallback `inspect/1` with `raise SnakeBridge.SerializationError`.

This forces users to either:
1. Pass primitives/lists/maps/tuples/bytes/datetime/etc.
2. Create Python objects via `call_dynamic` and pass refs
3. Implement a protocol for custom types (future enhancement)

## Implementation Details

### File: `lib/snakebridge/serialization_error.ex` (NEW)

```elixir
defmodule SnakeBridge.SerializationError do
  @moduledoc """
  Raised when attempting to encode a value that cannot be serialized for Python.

  SnakeBridge supports encoding:
  - Primitives: `nil`, booleans, integers, floats, strings
  - Collections: lists, maps, tuples, MapSets
  - Special types: atoms, DateTime, Date, Time, SnakeBridge.Bytes
  - References: SnakeBridge.Ref, SnakeBridge.StreamRef
  - Functions: anonymous functions (as callbacks)
  - Special floats: `:infinity`, `:neg_infinity`, `:nan`

  Types that cannot be serialized:
  - PIDs, ports, references
  - Custom structs without serialization support
  - File handles, sockets, other system resources

  ## Resolution

  For unsupported types, you have several options:

  1. **Create a Python object and pass the ref**:
     ```elixir
     {:ok, ref} = SnakeBridge.call("module", "create_object", [...])
     SnakeBridge.call("module", "use_object", [ref])
     ```

  2. **Convert to a supported type**:
     ```elixir
     # Instead of passing a PID
     SnakeBridge.call("module", "fn", [inspect(pid)])
     # Or extract relevant data
     SnakeBridge.call("module", "fn", [pid_to_list(pid)])
     ```

  3. **Use explicit bytes for binary data**:
     ```elixir
     SnakeBridge.call("module", "fn", [SnakeBridge.bytes(binary)])
     ```
  """

  defexception [:message, :value, :type]

  @type t :: %__MODULE__{
    message: String.t(),
    value: term(),
    type: atom() | String.t()
  }

  @impl true
  def exception(opts) do
    value = Keyword.fetch!(opts, :value)
    type = get_type(value)

    message = """
    Cannot serialize value of type #{type} for Python.

    Value: #{inspect(value, limit: 50, printable_limit: 100)}

    SnakeBridge cannot automatically serialize this type. See the module documentation
    for SnakeBridge.SerializationError for resolution options.
    """

    %__MODULE__{
      message: message,
      value: value,
      type: type
    }
  end

  defp get_type(value) when is_pid(value), do: :pid
  defp get_type(value) when is_port(value), do: :port
  defp get_type(value) when is_reference(value), do: :reference
  defp get_type(%{__struct__: struct_name}), do: struct_name
  defp get_type(value), do: inspect(value.__struct__ || :unknown)
end
```

### File: `lib/snakebridge/types/encoder.ex`

Replace the fallback clause:

```elixir
# REMOVE this:
# def encode(other) do
#   inspect(other)
# end

# ADD this:
@doc """
Fallback clause for unsupported types. Raises SerializationError.
"""
def encode(other) do
  raise SnakeBridge.SerializationError, value: other
end
```

### Full Encoder with Explicit Type Coverage

For clarity, here's the recommended order of encode clauses:

```elixir
defmodule SnakeBridge.Types.Encoder do
  @moduledoc """
  Encodes Elixir values for transmission to Python.
  """

  alias SnakeBridge.SerializationError

  @doc """
  Encode an Elixir value for Python.

  ## Supported Types

  | Elixir Type | Python Type |
  |-------------|-------------|
  | `nil` | `None` |
  | `true`/`false` | `True`/`False` |
  | integers | `int` |
  | floats | `float` |
  | strings (UTF-8) | `str` |
  | `SnakeBridge.Bytes` | `bytes` |
  | lists | `list` |
  | maps (string keys) | `dict` |
  | maps (non-string keys) | `dict` (tagged) |
  | tuples | `tuple` |
  | `MapSet` | `set` |
  | atoms | symbol (tagged) |
  | `DateTime` | `datetime` |
  | `Date` | `date` |
  | `Time` | `time` |
  | `:infinity`/`:neg_infinity`/`:nan` | special float |
  | `SnakeBridge.Ref` | object reference |
  | `SnakeBridge.StreamRef` | iterator reference |
  | functions | callback reference |

  ## Raises

  - `SnakeBridge.SerializationError` for unsupported types (PIDs, ports, etc.)
  """
  @spec encode(term()) :: term()

  # Nil
  def encode(nil), do: nil

  # Booleans
  def encode(true), do: true
  def encode(false), do: false

  # Numbers
  def encode(int) when is_integer(int), do: int
  def encode(float) when is_float(float), do: float

  # Special float atoms
  def encode(:infinity), do: tagged("special_float", %{"value" => "infinity"})
  def encode(:neg_infinity), do: tagged("special_float", %{"value" => "neg_infinity"})
  def encode(:nan), do: tagged("special_float", %{"value" => "nan"})

  # Explicit bytes wrapper (must come before generic binary)
  def encode(%SnakeBridge.Bytes{data: data}) do
    tagged("bytes", %{"data" => Base.encode64(data)})
  end

  # Strings/binaries
  def encode(binary) when is_binary(binary) do
    if String.valid?(binary) do
      binary
    else
      tagged("bytes", %{"data" => Base.encode64(binary)})
    end
  end

  # Atoms (except special ones handled above)
  def encode(atom) when is_atom(atom) do
    tagged("atom", %{"value" => Atom.to_string(atom)})
  end

  # Lists
  def encode(list) when is_list(list) do
    Enum.map(list, &encode/1)
  end

  # Tuples
  def encode(tuple) when is_tuple(tuple) do
    elements = tuple |> Tuple.to_list() |> Enum.map(&encode/1)
    tagged("tuple", %{"elements" => elements})
  end

  # MapSet
  def encode(%MapSet{} = set) do
    elements = set |> MapSet.to_list() |> Enum.map(&encode/1)
    tagged("set", %{"elements" => elements})
  end

  # DateTime
  def encode(%DateTime{} = dt) do
    tagged("datetime", %{"value" => DateTime.to_iso8601(dt)})
  end

  # Date
  def encode(%Date{} = date) do
    tagged("date", %{"value" => Date.to_iso8601(date)})
  end

  # Time
  def encode(%Time{} = time) do
    tagged("time", %{"value" => Time.to_iso8601(time)})
  end

  # SnakeBridge.Ref
  def encode(%SnakeBridge.Ref{} = ref) do
    SnakeBridge.Ref.to_wire_format(ref)
  end

  # SnakeBridge.StreamRef
  def encode(%SnakeBridge.StreamRef{} = ref) do
    SnakeBridge.StreamRef.to_wire_format(ref)
  end

  # Snakepit.PyRef (legacy compatibility)
  def encode(%Snakepit.PyRef{} = ref) do
    # Normalize to standard ref format
    %{
      "__type__" => "ref",
      "__schema__" => 1,
      "id" => ref.id,
      "session_id" => ref.session_id,
      "python_module" => ref.python_module,
      "library" => ref.library
    }
  end

  # Functions (callbacks)
  def encode(fun) when is_function(fun) do
    {ref_id, pid} = SnakeBridge.CallbackRegistry.register(fun)
    arity = Function.info(fun)[:arity]

    %{
      "__type__" => "callback",
      "ref_id" => ref_id,
      "pid" => inspect(pid),
      "arity" => arity
    }
  end

  # Maps - must come after all struct handlers
  def encode(%{} = map) when map_size(map) == 0, do: %{}

  def encode(%{} = map) do
    if all_string_keys?(map) do
      encode_string_key_map(map)
    else
      encode_tagged_dict(map)
    end
  end

  # FALLBACK - Unsupported types
  def encode(other) do
    raise SerializationError, value: other
  end

  # Private helpers
  defp tagged(type, payload) do
    Map.merge(%{"__type__" => type, "__schema__" => 1}, payload)
  end

  defp all_string_keys?(map) do
    Enum.all?(map, fn {key, _} ->
      is_binary(key) or (is_atom(key) and key not in [nil, true, false])
    end)
  end

  defp encode_string_key_map(map) do
    Map.new(map, fn {key, value} ->
      string_key = if is_atom(key), do: Atom.to_string(key), else: key
      {string_key, encode(value)}
    end)
  end

  defp encode_tagged_dict(map) do
    pairs = Enum.map(map, fn {key, value} ->
      [encode(key), encode(value)]
    end)
    tagged("dict", %{"pairs" => pairs})
  end
end
```

## Test Specifications

### File: `test/snakebridge/serialization_error_test.exs` (NEW)

```elixir
defmodule SnakeBridge.SerializationErrorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.SerializationError

  describe "SerializationError" do
    test "exception message includes value and type" do
      error = SerializationError.exception(value: self())

      assert error.type == :pid
      assert error.value == self()
      assert error.message =~ "Cannot serialize value of type"
      assert error.message =~ "pid"
    end

    test "exception for port" do
      # Create a port for testing
      port = Port.open({:spawn, "cat"}, [:binary])
      error = SerializationError.exception(value: port)

      assert error.type == :port
      Port.close(port)
    end

    test "exception for reference" do
      ref = make_ref()
      error = SerializationError.exception(value: ref)

      assert error.type == :reference
    end

    test "exception for custom struct" do
      defmodule TestStruct do
        defstruct [:field]
      end

      error = SerializationError.exception(value: %TestStruct{field: "value"})
      assert error.type == TestStruct
    end
  end
end
```

### File: `test/snakebridge/types/encoder_test.exs` (additions)

```elixir
describe "encode/1 unsupported types" do
  test "raises SerializationError for PID" do
    assert_raise SnakeBridge.SerializationError, fn ->
      Encoder.encode(self())
    end
  end

  test "raises SerializationError for port" do
    port = Port.open({:spawn, "cat"}, [:binary])
    assert_raise SnakeBridge.SerializationError, fn ->
      Encoder.encode(port)
    end
    Port.close(port)
  end

  test "raises SerializationError for reference" do
    assert_raise SnakeBridge.SerializationError, fn ->
      Encoder.encode(make_ref())
    end
  end

  test "raises SerializationError for unknown struct" do
    defmodule UnknownStruct do
      defstruct [:data]
    end

    assert_raise SnakeBridge.SerializationError, fn ->
      Encoder.encode(%UnknownStruct{data: "test"})
    end
  end

  test "error message contains value info" do
    error = assert_raise SnakeBridge.SerializationError, fn ->
      Encoder.encode(self())
    end

    assert error.message =~ "pid"
    assert error.message =~ "Cannot serialize"
  end

  test "does not raise for supported types" do
    # All these should encode without error
    supported_values = [
      nil,
      true,
      false,
      42,
      3.14,
      "hello",
      :atom,
      [1, 2, 3],
      %{a: 1},
      {1, 2, 3},
      MapSet.new([1, 2]),
      DateTime.utc_now(),
      Date.utc_today(),
      Time.utc_now(),
      :infinity,
      :neg_infinity,
      :nan,
      SnakeBridge.bytes("data"),
      fn x -> x end
    ]

    for value <- supported_values do
      assert Encoder.encode(value) != nil
    end
  end
end
```

### File: `test/snakebridge/encoder_error_integration_test.exs` (NEW)

```elixir
defmodule SnakeBridge.EncoderErrorIntegrationTest do
  use ExUnit.Case, async: true

  describe "call with unsupported argument type" do
    test "raises SerializationError before making Python call" do
      assert_raise SnakeBridge.SerializationError, fn ->
        SnakeBridge.call("math", "sqrt", [self()])
      end
    end

    test "error message helps user understand the problem" do
      error = catch_error(SnakeBridge.call("math", "sqrt", [make_ref()]))

      assert %SnakeBridge.SerializationError{} = error
      assert error.message =~ "reference"
      assert error.message =~ "Cannot serialize"
    end
  end

  describe "nested unsupported types" do
    test "raises for PID nested in list" do
      assert_raise SnakeBridge.SerializationError, fn ->
        SnakeBridge.call("lib", "fn", [[1, self(), 3]])
      end
    end

    test "raises for PID nested in map" do
      assert_raise SnakeBridge.SerializationError, fn ->
        SnakeBridge.call("lib", "fn", [%{pid: self()}])
      end
    end

    test "raises for PID nested in tuple" do
      assert_raise SnakeBridge.SerializationError, fn ->
        SnakeBridge.call("lib", "fn", [{1, self()}])
      end
    end
  end
end
```

## Edge Cases

1. **Nested unsupported types**: Error should propagate from nested structures
2. **Empty values**: `nil`, `[]`, `%{}`, `{}` should still work
3. **Struct without encoder**: Should raise, not fall through to map encoding
4. **Function with env capturing unsupported type**: Function itself encodes, captured values are not serialized

## Backwards Compatibility

**Breaking Change**: Code that previously "worked" by accident (passing PIDs, etc.) will now raise.

This is intentional - the old behavior was a silent bug waiting to cause problems in production.

### Migration Guide

**Before** (silent corruption):
```elixir
# This "worked" but sent garbage to Python
SnakeBridge.call("lib", "fn", [self()])
# Python received "#PID<0.123.0>" string
```

**After** (explicit error):
```elixir
# This now raises SerializationError
SnakeBridge.call("lib", "fn", [self()])

# Fix: Send what you actually need
SnakeBridge.call("lib", "fn", [inspect(self())])  # If you need the string
# Or: Don't pass process references to Python
```

## Related Changes

- Works with all other type changes in this MVP
- Error message references [03-explicit-bytes.md](./03-explicit-bytes.md) for bytes solution
- Complements [06-python-ref-safety.md](./06-python-ref-safety.md) for fail-fast behavior
