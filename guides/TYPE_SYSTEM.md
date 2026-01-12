# Type System

SnakeBridge implements a tagged JSON type system for lossless Elixir-Python round-trips.
Values that map directly to JSON pass through unchanged. Types without direct JSON
equivalents use tagged representations with `__type__` markers.

## Schema Version and Format

The current schema version is `1`. Tagged values follow this structure:

```json
{"__type__": "<type_tag>", "__schema__": 1, "<payload_key>": "<value>"}
```

Both Elixir and Python encoders produce identical wire formats.

## Primitive Types

Primitives pass through JSON encoding without tagging:

| Python | Elixir | JSON |
|--------|--------|------|
| `None` | `nil` | `null` |
| `True` / `False` | `true` / `false` | `true` / `false` |
| `int` | `integer()` | number |
| `float` | `float()` | number |
| `str` | `String.t()` | string |

## Tagged Types

### Bytes

```json
{"__type__": "bytes", "__schema__": 1, "data": "aGVsbG8="}
```

Binary data uses base64 encoding. Elixir decodes to raw binary.

### Tuple

```json
{"__type__": "tuple", "__schema__": 1, "elements": [1, 2, 3]}
```

Elixir tuples and Python tuples share this wire format.

### Complex Numbers

```json
{"__type__": "complex", "__schema__": 1, "real": 1.0, "imag": 2.0}
```

Elixir decodes these as maps: `%{real: 1.0, imag: 2.0}`.

### DateTime Types

```json
{"__type__": "datetime", "__schema__": 1, "value": "2026-01-11T12:00:00Z"}
{"__type__": "date", "__schema__": 1, "value": "2026-01-11"}
{"__type__": "time", "__schema__": 1, "value": "12:00:00"}
```

Elixir decodes to `DateTime`, `Date`, and `Time` structs.

### Set and Frozenset

```json
{"__type__": "set", "__schema__": 1, "elements": [1, 2, 3]}
{"__type__": "frozenset", "__schema__": 1, "elements": [1, 2, 3]}
```

Both decode to Elixir `MapSet`.

### Non-String Key Dict

```json
{"__type__": "dict", "__schema__": 1, "pairs": [[1, "one"], [2, "two"]]}
```

Preserves integer, tuple, or other non-string keys across the wire.

### Atom

```json
{"__type__": "atom", "__schema__": 1, "value": "ok"}
```

Security: Only allowlisted atoms are decoded (default: `["ok", "error"]`).

```elixir
config :snakebridge, atom_allowlist: ["ok", "error", "status"]
```

### Special Floats

```json
{"__type__": "special_float", "__schema__": 1, "value": "infinity"}
{"__type__": "special_float", "__schema__": 1, "value": "neg_infinity"}
{"__type__": "special_float", "__schema__": 1, "value": "nan"}
```

Elixir decodes as atoms: `:infinity`, `:neg_infinity`, `:nan`.

### Refs

```json
{"__type__": "ref", "__schema__": 1, "id": "abc123", "session_id": "xyz", "type_name": "Pattern"}
```

Non-serializable Python objects become refs. See Refs and Sessions guide.

### Stream Refs

```json
{"__type__": "stream_ref", "__schema__": 1, "id": "def456", "session_id": "xyz", "stream_type": "generator"}
```

Generators and iterators implement the `Enumerable` protocol.

### Callbacks

```json
{"__type__": "callback", "__schema__": 1, "ref_id": "cb789", "pid": "<0.123.0>", "arity": 2}
```

Elixir functions passed to Python for callbacks.

## Python to Elixir Type Mapping

Generated wrappers use these typespec mappings:

| Python Type | Elixir Typespec |
|-------------|-----------------|
| `int` | `integer()` |
| `float` | `float()` |
| `str` | `String.t()` |
| `bool` | `boolean()` |
| `bytes` | `binary()` |
| `None` | `nil` |
| `list[T]` | `list(T)` |
| `dict[K, V]` | `%{optional(K) => V}` |
| `tuple[T1, T2]` | `{T1, T2}` |
| `set[T]` | `MapSet.t(T)` |
| `Optional[T]` | `T \| nil` |
| `Union[T1, T2]` | `T1 \| T2` |
| `ClassName` | `ClassName.t()` |
| `Any` | `term()` |

## Encoding (Elixir to Python)

The encoder in `SnakeBridge.Types.Encoder` handles conversion:

```elixir
# Primitives pass through
encode(42)        # => 42
encode("hello")   # => "hello"

# Tuples are tagged
encode({:ok, 1})
# => %{"__type__" => "tuple", "__schema__" => 1,
#      "elements" => [%{"__type__" => "atom", ...}, 1]}

# MapSets are tagged
encode(MapSet.new([1, 2, 3]))
# => %{"__type__" => "set", "__schema__" => 1, "elements" => [1, 2, 3]}

# Maps with atom keys convert to string keys
encode(%{a: 1, b: 2})
# => %{"a" => 1, "b" => 2}

# Maps with non-string keys use tagged dict
encode(%{1 => "one", 2 => "two"})
# => %{"__type__" => "dict", "__schema__" => 1, "pairs" => [[1, "one"], [2, "two"]]}
```

## Decoding (Python to Elixir)

The decoder in `SnakeBridge.Types.Decoder` reconstructs Elixir types:

```elixir
# Primitives pass through
decode(42)        # => 42
decode("hello")   # => "hello"

# Tagged tuples become tuples
decode(%{"__type__" => "tuple", "elements" => [1, 2, 3]})
# => {1, 2, 3}

# Tagged sets become MapSets
decode(%{"__type__" => "set", "elements" => [1, 2, 3]})
# => #MapSet<[1, 2, 3]>

# Refs become SnakeBridge.Ref structs
decode(%{"__type__" => "ref", "id" => "abc", "session_id" => "xyz"})
# => %SnakeBridge.Ref{id: "abc", session_id: "xyz", ...}
```

## Using SnakeBridge.bytes/1

By default, UTF-8 valid Elixir binaries encode as Python strings. Use
`SnakeBridge.bytes/1` when Python expects `bytes`:

```elixir
# Without bytes wrapper - TypeError: Strings must be encoded before hashing
{:ok, _} = SnakeBridge.call("hashlib", "md5", ["abc"])

# With bytes wrapper - works correctly
{:ok, hash} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])

# Binary data for protocols
{:ok, _} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])
```

Non-UTF-8 binaries automatically encode as bytes:

```elixir
binary = <<0, 1, 2, 255>>
{:ok, _} = SnakeBridge.call("module", "process_bytes", [binary])
```

## Graceful Serialization

Graceful serialization preserves container structure when returning Python data.
Only non-serializable leaf values become refs, not entire containers.

### Container Preservation

```python
# Python returns:
{"name": "validator", "required": True, "pattern": re.compile(r"...")}
```

```elixir
# Elixir receives:
%{
  "name" => "validator",           # direct access
  "required" => true,              # direct access
  "pattern" => %SnakeBridge.Ref{}  # usable ref
}
```

### Leaf-Level Ref Creation

Only the non-serializable value becomes a ref:

```python
[1, 2, re.compile(r"^\d+$"), 4]
```

```elixir
[1, 2, %SnakeBridge.Ref{type_name: "Pattern"}, 4]

# Access serializable elements directly
Enum.at(result, 0)  # => 1

# Use ref for Python operations
pattern = Enum.at(result, 2)
{:ok, match} = SnakeBridge.method(pattern, "match", ["123"])
```

### Mixed Structures

Deeply nested structures preserve all levels:

```python
{"level1": {"level2": {"level3": [1, 2, re.compile(r"..."), 4]}}}
```

```elixir
# All levels preserved, only the pattern becomes a ref
result["level1"]["level2"]["level3"]
# => [1, 2, %SnakeBridge.Ref{}, 4]
```

### Working with Refs in Containers

```elixir
{:ok, config} = SnakeBridge.call("validators", "get_config", [])

# Access serializable fields directly
config["name"]      # => "phone_validator"
config["required"]  # => true

# Use ref for Python operations
pattern = config["pattern"]
{:ok, match} = SnakeBridge.method(pattern, "match", ["555-1234"])
{:ok, pattern_str} = SnakeBridge.attr(pattern, "pattern")
```

### Generators in Containers

Generators become `StreamRef` while the container remains accessible:

```python
{"status": "ok", "stream": (x for x in range(10))}
```

```elixir
%{"status" => "ok", "stream" => %SnakeBridge.StreamRef{}}

result["status"]              # => "ok"
result["stream"] |> Enum.take(5)  # => [0, 1, 2, 3, 4]
```

## See Also

- [Refs and Sessions](REFS_AND_SESSIONS.md) - Working with Python object refs
- [Streaming](STREAMING.md) - StreamRef and lazy iteration
- [Universal FFI](UNIVERSAL_FFI.md) - Runtime API for Python calls
