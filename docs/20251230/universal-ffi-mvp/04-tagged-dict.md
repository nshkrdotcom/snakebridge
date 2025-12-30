# Fix #4: Tagged Dict for Non-String Keys

**Status**: Specification
**Priority**: High
**Complexity**: Medium
**Estimated Changes**: ~100 lines Elixir, ~60 lines Python

## Problem Statement

`Types.Encoder.encode/1` for maps converts all keys to strings:

```elixir
def encode(%{} = map) do
  Map.new(map, fn {key, value} ->
    encoded_key = cond do
      is_atom(key) -> Atom.to_string(key)
      is_binary(key) -> key
      true -> encode(key)  # ← Problem: encodes but then uses as string key
    end
    {encoded_key, encode(value)}
  end)
end
```

On the Python side, `snakebridge_types.py` also forces dict keys to strings via `encode_dict_key`, which is lossy.

This breaks real APIs because Python dict keys are frequently:
- **Integers**: `{0: "first", 1: "second"}`
- **Tuples**: `{(x, y): value}` (coordinate maps, multi-dimensional indexing)
- **Enums**: `{Color.RED: "#ff0000"}`
- **Mixed**: API responses with integer status codes as keys

**Example failure**:
```elixir
# Elixir map with integer keys
%{1 => "one", 2 => "two"}

# Current encoding (WRONG)
{"1": "one", "2": "two"}  # Keys coerced to strings!

# Python receives string keys
{"1": "one", "2": "two"}  # API expecting int keys fails
```

## Solution

Introduce a tagged dict representation for maps/dicts with non-string keys.

### Wire Format

**All string keys** (unchanged):
```json
{"key1": "value1", "key2": "value2"}
```

**Non-string keys** (new tagged format):
```json
{
  "__type__": "dict",
  "__schema__": 1,
  "pairs": [
    [<encoded_key_1>, <encoded_value_1>],
    [<encoded_key_2>, <encoded_value_2>]
  ]
}
```

### Examples

**Integer keys**:
```elixir
%{1 => "one", 2 => "two"}
```
```json
{
  "__type__": "dict",
  "__schema__": 1,
  "pairs": [[1, "one"], [2, "two"]]
}
```

**Tuple keys**:
```elixir
%{{0, 0} => "origin", {1, 1} => "diagonal"}
```
```json
{
  "__type__": "dict",
  "__schema__": 1,
  "pairs": [
    [{"__type__": "tuple", "__schema__": 1, "elements": [0, 0]}, "origin"],
    [{"__type__": "tuple", "__schema__": 1, "elements": [1, 1]}, "diagonal"]
  ]
}
```

**Mixed keys**:
```elixir
%{:status => 200, "message" => "OK", 1 => "first"}
```
```json
{
  "__type__": "dict",
  "__schema__": 1,
  "pairs": [
    [{"__type__": "atom", "__schema__": 1, "value": "status"}, 200],
    ["message", "OK"],
    [1, "first"]
  ]
}
```

## Implementation Details

### File: `lib/snakebridge/types/encoder.ex`

Replace the map encoding:

```elixir
@doc """
Encodes a map.

If all keys are strings (or atoms that become strings), encodes as a plain JSON object.
If any key is not a string/atom, encodes as a tagged dict with key-value pairs.
"""
def encode(%{} = map) when map_size(map) == 0 do
  %{}
end

def encode(%{} = map) do
  if all_string_keys?(map) do
    encode_string_key_map(map)
  else
    encode_tagged_dict(map)
  end
end

defp all_string_keys?(map) do
  Enum.all?(map, fn {key, _value} ->
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

# Helper for tagged values (may already exist)
defp tagged(type, payload) do
  Map.merge(%{"__type__" => type, "__schema__" => 1}, payload)
end
```

### File: `lib/snakebridge/types/decoder.ex`

Add decoding for tagged dict:

```elixir
@doc """
Decodes a tagged dict back to an Elixir map.
"""
def decode(%{"__type__" => "dict", "pairs" => pairs}) when is_list(pairs) do
  pairs
  |> Enum.map(fn
    [key, value] -> {decode(key), decode(value)}
    # Handle legacy format if needed
    pair when is_list(pair) and length(pair) == 2 ->
      [key, value] = pair
      {decode(key), decode(value)}
  end)
  |> Map.new()
end

# Also handle schema version for future compatibility
def decode(%{"__type__" => "dict", "__schema__" => 1, "pairs" => pairs}) do
  decode(%{"__type__" => "dict", "pairs" => pairs})
end
```

**Important**: This clause must come before the generic map decoding clause.

### File: `priv/python/snakebridge_types.py`

#### Update `encode()` function:

```python
def encode(value):
    """Encode a Python value for transmission to Elixir."""
    # ... existing type checks ...

    if isinstance(value, dict):
        return encode_dict(value)

    # ... rest of encoding ...


def encode_dict(d):
    """
    Encode a dictionary.

    If all keys are strings, returns a plain dict (JSON object).
    If any key is not a string, returns a tagged dict with pairs.
    """
    if not d:
        return {}

    # Check if all keys are strings
    all_string_keys = all(isinstance(k, str) for k in d.keys())

    if all_string_keys:
        return {k: encode(v) for k, v in d.items()}
    else:
        # Non-string keys: use tagged dict format
        pairs = [[encode(k), encode(v)] for k, v in d.items()]
        return {
            "__type__": "dict",
            "__schema__": 1,
            "pairs": pairs
        }
```

#### Update `decode()` function:

```python
def decode(value, session_id=None, context=None):
    """Decode an Elixir-encoded value to Python."""
    # ... existing code ...

    if isinstance(value, dict):
        type_tag = value.get("__type__")

        if type_tag == "dict":
            return decode_tagged_dict(value, session_id, context)

        # ... other type handling ...

        # Plain dict (no __type__ or unrecognized)
        return {k: decode(v, session_id, context) for k, v in value.items()}


def decode_tagged_dict(value, session_id=None, context=None):
    """Decode a tagged dict with potentially non-string keys."""
    pairs = value.get("pairs", [])
    result = {}

    for pair in pairs:
        if isinstance(pair, list) and len(pair) == 2:
            key = decode(pair[0], session_id, context)
            val = decode(pair[1], session_id, context)
            result[key] = val

    return result
```

#### Remove lossy `encode_dict_key()`:

The old `encode_dict_key()` function that forced all keys to strings should be removed or deprecated:

```python
# DEPRECATED - remove or mark as deprecated
# def encode_dict_key(key):
#     """Convert any key to string (LOSSY - DO NOT USE)."""
#     ...
```

## Test Specifications

### File: `test/snakebridge/types/encoder_test.exs` (additions)

```elixir
describe "encode/1 maps with non-string keys" do
  test "encodes map with string keys as plain object" do
    map = %{"a" => 1, "b" => 2}
    encoded = Encoder.encode(map)

    # Plain JSON object, no __type__ tag
    assert encoded == %{"a" => 1, "b" => 2}
    refute Map.has_key?(encoded, "__type__")
  end

  test "encodes map with atom keys as plain object" do
    map = %{a: 1, b: 2}
    encoded = Encoder.encode(map)

    assert encoded == %{"a" => 1, "b" => 2}
    refute Map.has_key?(encoded, "__type__")
  end

  test "encodes map with integer keys as tagged dict" do
    map = %{1 => "one", 2 => "two"}
    encoded = Encoder.encode(map)

    assert %{
      "__type__" => "dict",
      "__schema__" => 1,
      "pairs" => pairs
    } = encoded

    # Sort for deterministic comparison
    sorted_pairs = Enum.sort(pairs)
    assert sorted_pairs == [[1, "one"], [2, "two"]]
  end

  test "encodes map with tuple keys as tagged dict" do
    map = %{{0, 0} => "origin", {1, 1} => "point"}
    encoded = Encoder.encode(map)

    assert %{"__type__" => "dict", "pairs" => pairs} = encoded
    assert length(pairs) == 2

    # Each key should be encoded as tuple
    Enum.each(pairs, fn [key, _value] ->
      assert %{"__type__" => "tuple"} = key
    end)
  end

  test "encodes map with mixed keys as tagged dict" do
    map = %{:atom_key => 1, "string_key" => 2, 42 => 3}
    encoded = Encoder.encode(map)

    # Has integer key, so must be tagged dict
    assert %{"__type__" => "dict", "pairs" => pairs} = encoded
    assert length(pairs) == 3
  end

  test "encodes empty map" do
    assert Encoder.encode(%{}) == %{}
  end

  test "encodes nested maps with non-string keys" do
    map = %{
      "outer" => %{1 => "inner_int_key"},
      2 => %{"nested" => "value"}
    }
    encoded = Encoder.encode(map)

    # Outer map has int key (2), so tagged
    assert %{"__type__" => "dict"} = encoded
  end

  test "preserves key types through encoding" do
    map = %{1 => "int", 1.5 => "float", :atom => "atom", {1, 2} => "tuple"}
    encoded = Encoder.encode(map)

    assert %{"__type__" => "dict", "pairs" => pairs} = encoded

    # Find each key type in pairs
    keys = Enum.map(pairs, fn [k, _v] -> k end)

    assert 1 in keys
    assert 1.5 in keys
    assert %{"__type__" => "atom", "value" => "atom"} in keys
    assert %{"__type__" => "tuple", "elements" => [1, 2]} in keys
  end
end
```

### File: `test/snakebridge/types/decoder_test.exs` (additions)

```elixir
describe "decode/1 tagged dict" do
  test "decodes tagged dict with integer keys" do
    encoded = %{
      "__type__" => "dict",
      "__schema__" => 1,
      "pairs" => [[1, "one"], [2, "two"]]
    }

    decoded = Decoder.decode(encoded)
    assert decoded == %{1 => "one", 2 => "two"}
  end

  test "decodes tagged dict with tuple keys" do
    encoded = %{
      "__type__" => "dict",
      "__schema__" => 1,
      "pairs" => [
        [%{"__type__" => "tuple", "elements" => [0, 0]}, "origin"],
        [%{"__type__" => "tuple", "elements" => [1, 1]}, "point"]
      ]
    }

    decoded = Decoder.decode(encoded)
    assert decoded == %{{0, 0} => "origin", {1, 1} => "point"}
  end

  test "decodes tagged dict with mixed keys" do
    encoded = %{
      "__type__" => "dict",
      "pairs" => [
        ["string_key", 1],
        [42, 2],
        [%{"__type__" => "atom", "value" => "ok"}, 3]
      ]
    }

    decoded = Decoder.decode(encoded)
    assert decoded["string_key"] == 1
    assert decoded[42] == 2
    # Atom decoding depends on allowlist
  end

  test "decodes empty tagged dict" do
    encoded = %{"__type__" => "dict", "pairs" => []}
    assert Decoder.decode(encoded) == %{}
  end

  test "decodes nested tagged dicts" do
    encoded = %{
      "__type__" => "dict",
      "pairs" => [
        [1, %{"__type__" => "dict", "pairs" => [[2, "nested"]]}]
      ]
    }

    decoded = Decoder.decode(encoded)
    assert decoded == %{1 => %{2 => "nested"}}
  end
end
```

### File: `test/snakebridge/tagged_dict_integration_test.exs` (NEW)

```elixir
defmodule SnakeBridge.TaggedDictIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  describe "round-trip non-string key maps" do
    test "integer key map round-trip" do
      input = %{1 => "one", 2 => "two", 3 => "three"}

      # Echo through Python (identity function)
      {:ok, result} = SnakeBridge.call("builtins", "dict", [input])

      assert result == input
    end

    test "tuple key map round-trip" do
      input = %{{0, 0} => "origin", {1, 0} => "x-axis", {0, 1} => "y-axis"}

      {:ok, result} = SnakeBridge.call("builtins", "dict", [input])

      assert result == input
    end

    test "Python function receives integer keys correctly" do
      # Python: dict.get(1) should work when key is int, not string
      input = %{1 => "found", 2 => "also"}

      # Create dict and call get with integer key
      {:ok, ref} = SnakeBridge.call("builtins", "dict", [input])
      {:ok, value} = SnakeBridge.Dynamic.call(ref, :get, [1])

      assert value == "found"
    end
  end

  describe "Python returns non-string key dicts" do
    test "receives dict with int keys from Python" do
      # Create a dict with int keys in Python
      # dict([(1, "one"), (2, "two")])
      pairs = [[1, "one"], [2, "two"]]
      {:ok, result} = SnakeBridge.call("builtins", "dict", [pairs])

      assert result[1] == "one"
      assert result[2] == "two"
    end

    test "receives dict with tuple keys from Python" do
      # Python: {(0,0): "origin"}
      {:ok, ref} = SnakeBridge.call("builtins", "eval", ["{(0,0): 'origin', (1,1): 'diagonal'}"])

      # ref should decode to map with tuple keys
      # (depends on whether eval returns ref or decoded value)
    end
  end
end
```

## Edge Cases

1. **Empty map**: Should encode as `{}` (not tagged dict)
2. **Single integer key**: Should use tagged dict format
3. **nil as key**: `%{nil => "value"}` - nil should be encoded as key
4. **true/false as keys**: `%{true => 1, false => 0}` - preserve as boolean keys
5. **Nested maps**: Inner maps with non-string keys should also be tagged
6. **Large maps**: Performance should be acceptable for thousands of keys
7. **Duplicate keys after encoding**: Shouldn't happen (Elixir maps don't have dupes)

## Performance Considerations

- **String-key fast path**: Most maps have string/atom keys, use plain JSON
- **Detection cost**: One pass to check `all_string_keys?` before encoding
- **Pairs format**: Slightly larger wire size than plain JSON objects
- **Decoding**: O(n) to reconstruct map from pairs

## Backwards Compatibility

### Wire Format

**Old format** (lossy, keys coerced to strings):
```json
{"1": "one", "2": "two"}
```

**New format** (lossless):
```json
{"__type__": "dict", "pairs": [[1, "one"], [2, "two"]]}
```

### Migration

- **Elixir encoder**: New behavior immediately (no opt-in needed)
- **Python decoder**: Must be updated to handle `__type__: "dict"`
- **Python encoder**: Should be updated to emit tagged dicts
- **Old Python adapter**: Will see tagged dicts as regular objects (with `__type__` as string key)

### Compatibility Strategy

1. Update Python adapter first (can decode both formats)
2. Update Elixir encoder (starts emitting tagged dicts)
3. Old Elixir decoders will see tagged dicts as maps with `__type__` key (degraded but not broken)

## Related Changes

- Complements [03-explicit-bytes.md](./03-explicit-bytes.md) for complete type coverage
- Used by [07-universal-api.md](./07-universal-api.md) in public API surface
- Requires [06-python-ref-safety.md](./06-python-ref-safety.md) Python-side changes
