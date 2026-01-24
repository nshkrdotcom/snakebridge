# SnakeBridge Best Practices

Consolidated patterns and recommendations for robust SnakeBridge applications.

## 1. API Usage Patterns

### Decision Tree: Universal FFI vs Generated Wrappers

```
Need to call Python?
    +-- Core library called frequently? --> Generated Wrappers
    +-- Runtime-determined module? -------> Universal FFI
    +-- Prototyping/one-off calls? -------> Universal FFI
    +-- Otherwise -----------------------> Consider adding to python_deps
```

### Universal FFI (Most Cases)

```elixir
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])
{:ok, rounded} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
{:ok, pi} = SnakeBridge.get("math", "pi")

{:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
{:ok, exists?} = SnakeBridge.method(path, "exists", [])
{:ok, name} = SnakeBridge.attr(path, "name")
```

### Generated Wrappers (Production Core Libraries)

```elixir
# mix.exs
config :snakebridge, python_deps: [{:numpy, ">=1.20"}, {:pandas, ">=2.0"}]

# Usage
{:ok, array} = Python.Numpy.array([[1, 2], [3, 4]])
```

Both approaches coexist in the same project.

## 2. Session Management

### Auto-Sessions (Default)

```elixir
{:ok, _} = SnakeBridge.call("math", "sqrt", [16])  # Creates session
session_id = SnakeBridge.current_session()         # "auto_..."

# All refs share the session
{:ok, ref1} = SnakeBridge.call("pathlib", "Path", ["."])
{:ok, ref2} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
ref1.session_id == ref2.session_id  # true
```

### Explicit Sessions (Cross-Process)

```elixir
SessionContext.with_session([session_id: "shared_pipeline"], fn ->
  {:ok, model} = load_model()
  # Other processes can use "shared_pipeline" to access this model
end)
```

### Release Strategies

| Strategy | Use Case | Code |
|----------|----------|------|
| Automatic | Most cases | Process exit triggers cleanup |
| Manual | Large objects | `SnakeBridge.release_auto_session()` |
| TTL | Long-running | `config :snakebridge, ref_ttl: 3600` |

## 3. Affinity Selection

See [SESSION_AFFINITY.md](SESSION_AFFINITY.md) for details.

| Mode | Behavior | Use Case |
|------|----------|----------|
| `:hint` | Best-effort, may fall back | Stateless calls |
| `:strict_queue` | Queue for preferred worker | Stateful refs, models |
| `:strict_fail_fast` | Error if busy | Latency-sensitive with retry |

```elixir
# Global
SnakeBridge.ConfigHelper.configure_snakepit!(pool_size: 4, affinity: :strict_queue)

# Per-call
SnakeBridge.call("pathlib", "Path", ["."], __runtime__: [affinity: :strict_fail_fast])
```

## 4. Error Handling Strategies

### Pattern Matching

```elixir
case SnakeBridge.call("math", "sqrt", [-1]) do
  {:ok, result} -> handle_success(result)
  {:error, %{python_type: "ValueError"}} -> {:error, :invalid_input}
  {:error, reason} -> {:error, :unknown}
end
```

### Structured Errors (ML Workloads)

```elixir
config :snakebridge, error_mode: :translated

case train_model(data) do
  {:error, %SnakeBridge.Error.ShapeMismatchError{}} -> reduce_dimensions()
  {:error, %SnakeBridge.Error.OutOfMemoryError{}} -> reduce_batch_size()
  {:error, %SnakeBridge.Error.DtypeMismatchError{}} -> cast_types()
end
```

### Bang Variants

```elixir
input
|> SnakeBridge.call!("json", "loads", [&1])
|> SnakeBridge.call!("processor", "transform", [&1])
```

## 5. Streaming Patterns

| Data Size | Approach |
|-----------|----------|
| < 1000 items | Convert to list in Python |
| 1000-100K | StreamRef with Enum |
| > 100K | Native gRPC streaming |

```elixir
# Small: convert in Python (1 round-trip)
{:ok, range} = SnakeBridge.call("builtins", "range", [100])
{:ok, items} = SnakeBridge.call("builtins", "list", [range])

# Large: lazy iteration
{:ok, stream} = SnakeBridge.call("itertools", "islice", [generator, 1000])
first_10 = Enum.take(stream, 10)

# High throughput: streaming callback
Python.Generator.produce_stream(source, [stream: true], &process_chunk/1)
```

## 6. Context Manager Pattern

```elixir
{:ok, file} = SnakeBridge.call("builtins", "open", [path, "w"])
SnakeBridge.with_python(file) do
  SnakeBridge.method!(file, :write, ["content"])
end
# File auto-closed via __exit__
```

## 7. Performance Tips

### Reduce Round-Trips

```elixir
# Bad: 4 round-trips
{:ok, a} = SnakeBridge.call("numpy", "array", [[1, 2, 3]])
{:ok, b} = SnakeBridge.call("numpy", "add", [a, [4, 5, 6]])

# Good: 1 round-trip with helper
# priv/python/helpers/math_ops.py
def add_arrays(a, b):
    return (np.array(a) + np.array(b)).tolist()

{:ok, result} = SnakeBridge.call_helper("math_ops.add_arrays", [[1,2,3], [4,5,6]])
```

### Batch Operations

```elixir
# Instead of N calls
Enum.map(items, &SnakeBridge.call("processor", "transform", [&1]))

# Single batched call
{:ok, results} = SnakeBridge.call("processor", "transform_batch", [items])
```

### Pool Sizing

```elixir
SnakeBridge.ConfigHelper.configure_snakepit!(pools: [
  %{name: :compute, pool_size: System.schedulers_online()},  # CPU-bound
  %{name: :io, pool_size: 20}                                 # IO-bound
])
```

## 8. Testing Patterns

```elixir
defmodule MyTest do
  use ExUnit.Case

  setup do
    SnakeBridge.Runtime.clear_auto_session()
    :ok
  end

  test "python integration" do
    {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
    assert result == 4.0
  end

  test "isolated session" do
    SessionContext.with_session([session_id: "test_#{:rand.uniform()}"], fn ->
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
      assert SnakeBridge.ref?(ref)
    end)
  end
end
```

## 9. Common Pitfalls and Solutions

### Ref Used After Session Release

```elixir
# Problem
{:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
SnakeBridge.release_auto_session()
SnakeBridge.method(ref, :exists, [])  # RefNotFoundError

# Solution: Extract data before release
{:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
{:ok, name} = SnakeBridge.attr(ref, "name")
SnakeBridge.release_auto_session()
```

### Cross-Process Refs Without Explicit Session

```elixir
# Problem: auto-sessions are process-scoped
{:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
Task.async(fn -> SnakeBridge.method(ref, :exists, []) end)  # May fail

# Solution: use explicit session
SessionContext.with_session([session_id: "shared"], fn ->
  {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
  Task.async(fn ->
    SessionContext.with_session([session_id: "shared"], fn ->
      SnakeBridge.method(ref, :exists, [])
    end)
  end) |> Task.await()
end)
```

### Strings Sent as Bytes

```elixir
# Problem: hashlib expects bytes
SnakeBridge.call("hashlib", "md5", ["hello"])  # Fails

# Solution: wrap with bytes/1
SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("hello")])
```

### Generator Exhaustion

```elixir
# Problem: generators are single-use
{:ok, gen} = SnakeBridge.call("builtins", "iter", [[1, 2, 3]])
Enum.to_list(gen)  # [1, 2, 3]
Enum.to_list(gen)  # [] - exhausted

# Solution: convert to list first
{:ok, items} = SnakeBridge.call("builtins", "list", [gen])
```

### Memory Growth from Forgotten Refs

```elixir
# Solution: configure TTL
config :snakebridge, ref_ttl: 1800  # 30 minutes

# Or release explicitly
{:ok, large_data} = process_data()
result = extract_values(large_data)
SnakeBridge.release_ref(large_data)
```

## 10. Callback Safety (v0.14.0+)

### Deadlock-Free Callbacks

As of v0.14.0, callbacks registered with `SnakeBridge.CallbackRegistry` are invoked
asynchronously via supervised tasks. This means:

- Callbacks can safely invoke other callbacks without deadlocking the registry
- Long-running callbacks don't block the registry from handling other requests
- Nested/recursive callback patterns now work correctly

```elixir
# Safe: callback invoking another callback
SnakeBridge.CallbackRegistry.register("outer", fn data ->
  # This would deadlock before v0.14.0
  SnakeBridge.CallbackRegistry.invoke("inner", data)
  :ok
end)

SnakeBridge.CallbackRegistry.register("inner", fn data ->
  process(data)
end)
```

### Session Cleanup Error Handling

Session cleanup now runs in supervised tasks and emits telemetry on failure.
Monitor cleanup errors to detect Python runtime issues:

```elixir
# Attach handler for cleanup failures
:telemetry.attach(
  "cleanup-monitor",
  [:snakebridge, :session, :cleanup, :error],
  fn _event, _measurements, metadata, _config ->
    Logger.warning("Cleanup failed: #{inspect(metadata.error)}")
  end,
  nil
)
```

Configure cleanup timeout to prevent indefinite waits:

```elixir
config :snakebridge, session_cleanup_timeout_ms: 10_000  # 10 seconds (default)
```

---

## See Also

- [SESSION_AFFINITY.md](SESSION_AFFINITY.md) - Affinity configuration
- [UNIVERSAL_FFI.md](UNIVERSAL_FFI.md) - Complete API reference
- [STREAMING.md](STREAMING.md) - Streaming patterns
- [ERROR_HANDLING.md](ERROR_HANDLING.md) - Error types and translation
