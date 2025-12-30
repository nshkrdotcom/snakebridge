# Prompt 01: Type System Foundation

**Objective**: Implement SnakeBridge.Bytes, tagged dict encoding, and SerializationError.

## Required Reading

Before starting, read these files completely:

### Documentation
- `docs/20251230/universal-ffi-mvp/00-overview.md` - Full context
- `docs/20251230/universal-ffi-mvp/03-explicit-bytes.md` - Bytes spec
- `docs/20251230/universal-ffi-mvp/04-tagged-dict.md` - Tagged dict spec
- `docs/20251230/universal-ffi-mvp/05-encoder-fallback.md` - Encoder fallback spec

### Source Files
- `lib/snakebridge/types/encoder.ex` - Current encoder implementation
- `lib/snakebridge/types/decoder.ex` - Current decoder implementation
- `priv/python/snakebridge_types.py` - Python type handling
- `test/snakebridge/types/encoder_test.exs` - Existing encoder tests
- `test/snakebridge/types/decoder_test.exs` - Existing decoder tests

## Implementation Tasks

### Task 1: Create SnakeBridge.Bytes struct

Create `lib/snakebridge/bytes.ex`:

```elixir
defmodule SnakeBridge.Bytes do
  @moduledoc """
  Wrapper struct for binary data that should be sent to Python as `bytes`, not `str`.
  [Full documentation from 03-explicit-bytes.md]
  """

  @type t :: %__MODULE__{data: binary()}
  defstruct [:data]

  @spec new(binary()) :: t()
  def new(data) when is_binary(data), do: %__MODULE__{data: data}

  @spec data(t()) :: binary()
  def data(%__MODULE__{data: data}), do: data
end
```

### Task 2: Create SnakeBridge.SerializationError

Create `lib/snakebridge/serialization_error.ex`:

```elixir
defmodule SnakeBridge.SerializationError do
  @moduledoc """
  Raised when attempting to encode a value that cannot be serialized for Python.
  [Full documentation from 05-encoder-fallback.md]
  """

  defexception [:message, :value, :type]

  @impl true
  def exception(opts) do
    value = Keyword.fetch!(opts, :value)
    type = get_type(value)
    message = build_message(value, type)
    %__MODULE__{message: message, value: value, type: type}
  end

  defp get_type(value) when is_pid(value), do: :pid
  defp get_type(value) when is_port(value), do: :port
  defp get_type(value) when is_reference(value), do: :reference
  defp get_type(%{__struct__: struct_name}), do: struct_name
  defp get_type(_), do: :unknown

  defp build_message(value, type) do
    # [Implementation from spec]
  end
end
```

### Task 3: Update Encoder

Modify `lib/snakebridge/types/encoder.ex`:

1. Add clause for `SnakeBridge.Bytes` (BEFORE generic binary clause):
   ```elixir
   def encode(%SnakeBridge.Bytes{data: data}) when is_binary(data) do
     tagged("bytes", %{"data" => Base.encode64(data)})
   end
   ```

2. Replace map encoding with tagged dict logic:
   ```elixir
   def encode(%{} = map) when map_size(map) == 0, do: %{}

   def encode(%{} = map) do
     if all_string_keys?(map) do
       encode_string_key_map(map)
     else
       encode_tagged_dict(map)
     end
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
   ```

3. Replace fallback clause:
   ```elixir
   # REMOVE: def encode(other), do: inspect(other)
   # ADD:
   def encode(other) do
     raise SnakeBridge.SerializationError, value: other
   end
   ```

### Task 4: Update Decoder

Modify `lib/snakebridge/types/decoder.ex`:

Add clause for tagged dict (BEFORE generic map clause):
```elixir
def decode(%{"__type__" => "dict", "pairs" => pairs}) when is_list(pairs) do
  pairs
  |> Enum.map(fn [key, value] -> {decode(key), decode(value)} end)
  |> Map.new()
end

def decode(%{"__type__" => "dict", "__schema__" => 1, "pairs" => pairs}) do
  decode(%{"__type__" => "dict", "pairs" => pairs})
end
```

### Task 5: Update Python Types

Modify `priv/python/snakebridge_types.py`:

1. Update `encode_dict()` function:
   ```python
   def encode_dict(d):
       if not d:
           return {}
       all_string_keys = all(isinstance(k, str) for k in d.keys())
       if all_string_keys:
           return {k: encode(v) for k, v in d.items()}
       else:
           pairs = [[encode(k), encode(v)] for k, v in d.items()]
           return {"__type__": "dict", "__schema__": 1, "pairs": pairs}
   ```

2. Update `decode()` to handle tagged dict:
   ```python
   if type_tag == "dict":
       return decode_tagged_dict(value, session_id, context)

   def decode_tagged_dict(value, session_id=None, context=None):
       pairs = value.get("pairs", [])
       return {decode(p[0], session_id, context): decode(p[1], session_id, context)
               for p in pairs if len(p) == 2}
   ```

### Task 6: Write Tests (TDD)

Create/update test files:

1. `test/snakebridge/bytes_test.exs` - Bytes struct tests
2. `test/snakebridge/serialization_error_test.exs` - Error tests
3. Update `test/snakebridge/types/encoder_test.exs`:
   - Add Bytes encoding tests
   - Add tagged dict encoding tests
   - Add SerializationError tests for PIDs, ports, refs
4. Update `test/snakebridge/types/decoder_test.exs`:
   - Add tagged dict decoding tests

## Verification Checklist

Run after implementation:

```bash
# Run tests
mix test test/snakebridge/bytes_test.exs
mix test test/snakebridge/serialization_error_test.exs
mix test test/snakebridge/types/encoder_test.exs
mix test test/snakebridge/types/decoder_test.exs
mix test

# Check types
mix dialyzer

# Check code quality
mix credo --strict

# Verify no warnings
mix compile --warnings-as-errors
```

All must pass with:
- ✅ All tests passing
- ✅ No dialyzer errors
- ✅ No credo issues
- ✅ No compilation warnings

## CHANGELOG Entry

Update `CHANGELOG.md` with entry for 0.8.4:

```markdown
## [0.8.4] - 2025-12-XX

### Added
- `SnakeBridge.Bytes` struct for explicit binary data encoding to Python `bytes`
- `SnakeBridge.SerializationError` exception for unsupported type encoding
- Tagged dict wire format for maps with non-string keys (integers, tuples, etc.)

### Changed
- Encoder now raises `SerializationError` instead of silently calling `inspect/1` on unknown types
- Maps with non-string keys are now encoded as tagged dicts with key-value pairs

### Fixed
- Maps with integer/tuple keys now serialize correctly instead of coercing keys to strings
```

## Notes

- Keep existing tests passing - don't break backwards compatibility for supported types
- The `SnakeBridge.Bytes` clause must come BEFORE the generic binary clause in encoder
- The tagged dict clause must come BEFORE the generic map clause in decoder
- Ensure proper `@spec` annotations for all new functions
- Add `@moduledoc` and `@doc` for all new modules/functions
