# Streaming Python Generators and Iterators

SnakeBridge provides first-class support for Python generators and iterators through the
`StreamRef` type. This allows lazy iteration over Python data sources from Elixir, with
full integration into the `Enumerable` protocol.

## StreamRef Overview

When a Python function returns a generator or iterator, SnakeBridge wraps it in a
`StreamRef` struct rather than eagerly consuming the entire sequence:

```elixir
defstruct [
  :ref_id,        # Unique identifier for the stream
  :session_id,    # Session tracking for lifecycle management
  :pool_name,     # Optional pool affinity
  :stream_type,   # "generator", "iterator", or "async_generator"
  :python_module, # Source module (e.g., "builtins", "itertools")
  :library,       # Library name for routing
  exhausted: false
]
```

### Stream Types

SnakeBridge recognizes three stream types:

| Type | Description | Example |
|------|-------------|---------|
| `"generator"` | Generator functions using `yield` | `(x for x in range(10))` |
| `"iterator"` | Objects with `__next__` and `__iter__` | `iter([1, 2, 3])` |
| `"async_generator"` | Async generators using `async yield` | `async def gen(): yield 1` |

## Generator Detection (Python Side)

The Python adapter automatically detects generators and iterators using the following logic:

```python
def _is_generator_or_iterator(value: Any) -> bool:
    if isinstance(value, types.GeneratorType):
        return True
    if hasattr(types, 'AsyncGeneratorType') and isinstance(value, types.AsyncGeneratorType):
        return True
    if hasattr(value, '__next__') and hasattr(value, '__iter__'):
        # Exclude built-in iterables that should serialize directly
        if isinstance(value, (str, bytes, list, tuple, dict, set, frozenset)):
            return False
        # Exclude context managers (file objects, connections)
        if hasattr(value, "__enter__") and hasattr(value, "__exit__"):
            return False
        return True
    return False
```

This detection ensures that standard collections serialize as values while true iterators
become StreamRefs for lazy consumption.

## Wire Format

StreamRefs are transmitted as tagged JSON objects:

```json
{
    "__type__": "stream_ref",
    "__schema__": 1,
    "id": "abc123",
    "session_id": "session_xyz",
    "stream_type": "generator",
    "type_name": "generator",
    "python_module": "builtins"
}
```

The Elixir decoder automatically converts this wire format into a `SnakeBridge.StreamRef`
struct, ready for iteration.

## Enumerable Protocol Integration

StreamRef implements the `Enumerable` protocol, making it compatible with all `Enum`
functions:

```elixir
# Create a Python range iterator
{:ok, stream} = SnakeBridge.call("builtins", "range", [10])

# Use standard Enum functions
first_five = Enum.take(stream, 5)       # [0, 1, 2, 3, 4]
total = Enum.sum(stream)                # 45
doubled = Enum.map(stream, &(&1 * 2))   # [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
list = Enum.to_list(stream)             # [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
```

### Protocol Implementation Details

The Enumerable implementation uses these callbacks:

| Callback | Behavior |
|----------|----------|
| `reduce/3` | Core iteration via `stream_next/2` |
| `count/1` | Returns `{:error, __MODULE__}` for generators; attempts `__len__` for iterators |
| `member?/2` | Returns `{:error, __MODULE__}` (cannot check membership without consuming) |
| `slice/1` | Returns `{:error, __MODULE__}` (random access not supported) |

Since most operations require consuming the stream, functions like `Enum.count/1` will
fall back to reduction, consuming the entire stream.

## The stream_next Protocol

Each iteration step calls `Runtime.stream_next/2`, which sends a request to the Python
adapter to advance the iterator:

```elixir
def stream_next(stream_ref, opts \\ []) do
  wire_ref = SnakeBridge.StreamRef.to_wire_format(stream_ref)
  session_id = resolve_session_id(runtime_opts, stream_ref)

  payload = %{
    "call_type" => "stream_next",
    "stream_ref" => wire_ref,
    "library" => library,
    "session_id" => session_id
  }

  case execute(payload) do
    {:ok, %{"__type__" => "stop_iteration"}} -> {:error, :stop_iteration}
    {:ok, value} -> {:ok, decode_value(value)}
    {:error, reason} -> {:error, reason}
  end
end
```

When the Python iterator is exhausted, it returns a `stop_iteration` sentinel that
signals the end of the stream.

## Usage Patterns

### Lazy Iteration

The primary benefit of StreamRef is lazy evaluation. Only the requested elements are
fetched from Python:

```elixir
# Create an infinite counter
{:ok, counter} = SnakeBridge.call("itertools", "count", [1])

# Fetch only what you need
first_ten = Enum.take(counter, 10)  # [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
# The iterator continues from where it left off
next_five = Enum.take(counter, 5)   # [11, 12, 13, 14, 15]
```

### Converting to List in Python

For small, bounded iterables, converting to a list in Python reduces round-trips:

```elixir
# Create a range reference
{:ok, range_ref} = SnakeBridge.call("builtins", "range", [100])

# Convert to list in Python (single round-trip)
{:ok, list} = SnakeBridge.call("builtins", "list", [range_ref])
# list = [0, 1, 2, ..., 99]
```

This is more efficient than iterating via StreamRef when you know the data is small.

### Streaming with Callbacks (Generated Wrappers)

Generated wrappers support streaming mode with callbacks for chunk processing:

```elixir
callback = fn chunk ->
  IO.puts("Received chunk: #{inspect(chunk)}")
  :ok
end

# Generated streaming function
MyPython.Module.generate_stream("input", [stream: true, count: 10], callback)
```

This uses native gRPC streaming for higher throughput than the per-item StreamRef protocol.

### Processing Large Datasets

Combine StreamRef with Stream functions for memory-efficient processing:

```elixir
{:ok, data_stream} = SnakeBridge.call("my_module", "load_large_dataset", [])

# Process in chunks without loading everything into memory
data_stream
|> Stream.chunk_every(100)
|> Stream.each(fn batch -> process_batch(batch) end)
|> Stream.run()
```

## Generators in Containers (Graceful Serialization)

With graceful serialization (v0.10.0+), generators embedded in containers are preserved
as StreamRefs while the container structure remains intact:

```python
# Python returns a dict with a generator
{"status": "ok", "data": (x * 2 for x in range(10))}
```

```elixir
# Elixir receives mixed structure
%{
  "status" => "ok",           # Direct value
  "data" => %StreamRef{}      # Lazy iterator
}

# Access the stream
result["status"]                    # "ok"
Enum.to_list(result["data"])       # [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
```

This allows Python functions to return rich structures containing both immediate values
and lazy sequences.

## Performance Considerations

### RPC-per-Item Overhead

Each `stream_next` call is a separate gRPC round-trip. This works well for:

- Moderate-sized streams (hundreds to thousands of items)
- Items that are expensive to compute
- Early termination patterns (taking first N items)

### When to Use Alternative Approaches

| Scenario | Recommendation |
|----------|----------------|
| Small, bounded data (<1000 items) | Convert to list in Python |
| High-throughput streaming | Use generated wrappers with native gRPC streaming |
| Infinite streams with early exit | StreamRef with `Enum.take/2` |
| Large data with batch processing | StreamRef with `Stream.chunk_every/2` |

### Session Affinity

StreamRefs carry their `session_id` and `pool_name`, ensuring subsequent `stream_next`
calls route to the same Python worker that holds the iterator state. See the
[Session Affinity](SESSION_AFFINITY.md) guide for configuration options.

## Async Generators

SnakeBridge recognizes async generators (`stream_type: "async_generator"`) in the wire
format, but current iteration uses synchronous consumption. The Python adapter calls
`next()` on the underlying iterator rather than `await anext()`.

For async Python code, consider:

1. Wrapping async generators in synchronous adapters on the Python side
2. Using generated wrappers with native async streaming support
3. Collecting async results into a list before returning

```python
# Python helper to synchronize async generator
async def collect_async(async_gen):
    return [item async for item in async_gen]
```

```elixir
# Call the synchronous wrapper
{:ok, results} = SnakeBridge.call("my_module", "collect_async", [async_gen_ref])
```

## See Also

- [Universal FFI](UNIVERSAL_FFI.md) - Core API for calling Python
- [Refs and Sessions](REFS_AND_SESSIONS.md) - Understanding ref lifecycle
- [Session Affinity](SESSION_AFFINITY.md) - Routing configuration for stateful streams
- [Type System](TYPE_SYSTEM.md) - Complete type mapping including StreamRef
