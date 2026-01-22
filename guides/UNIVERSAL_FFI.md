# Universal FFI

The Universal FFI enables calling **any** Python module dynamically at runtime, without compile-time
code generation. Use it for libraries not in your generated wrappers, one-off scripts, runtime-determined
module paths, or quick prototyping.

## Overview and Use Cases

**Use Universal FFI when:**
- Calling libraries not in your `python_deps` configuration
- Module paths are determined at runtime (plugins, user-specified modules)
- Writing quick scripts or one-off calls
- Prototyping before adding to generated wrappers

**Use Generated Wrappers when:**
- You have core libraries called frequently (NumPy, Pandas)
- You want compile-time type hints and IDE autocomplete
- Performance is critical (slightly faster hot path)

Both approaches coexist. Use generated wrappers for core libraries, Universal FFI for everything else.

## Core Functions

### call/4 and call!/4

Call any Python function by module path and function name.

```elixir
{:ok, 4.0} = SnakeBridge.call("math", "sqrt", [16])
{:ok, 3.14} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
{:ok, path} = SnakeBridge.call("os.path", "join", ["/home", "user", "file.txt"])
{:ok, ref} = SnakeBridge.call("pathlib", "Path", ["/tmp/example.txt"])

# Bang variant raises on error
result = SnakeBridge.call!("math", "sqrt", [16])  # => 4.0
```

Return values decode to Elixir types when JSON-serializable. Non-serializable Python objects
return as `%SnakeBridge.Ref{}` structs.

### get/3 and get!/3

Retrieve module-level attributes and constants.

```elixir
{:ok, 3.141592653589793} = SnakeBridge.get("math", "pi")
{:ok, sep} = SnakeBridge.get("os", "sep")  # => {:ok, "/"}
{:ok, path_class} = SnakeBridge.get("pathlib", "Path")  # Returns ref

pi = SnakeBridge.get!("math", "pi")  # Bang variant
```

### method/4 and method!/4

Call methods on Python object references.

```elixir
{:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/example.txt"])
{:ok, false} = SnakeBridge.method(path, "exists", [])
{:ok, true} = SnakeBridge.method(path, "is_absolute", [])
{:ok, child} = SnakeBridge.method(path, "joinpath", ["subdir", "file.txt"])

exists? = SnakeBridge.method!(path, "exists", [])  # Bang variant
```

### attr/3 and attr!/3

Access attributes on Python object references.

```elixir
{:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/example.txt"])
{:ok, "example.txt"} = SnakeBridge.attr(path, "name")
{:ok, ".txt"} = SnakeBridge.attr(path, "suffix")
{:ok, parent_ref} = SnakeBridge.attr(path, "parent")  # Returns ref

name = SnakeBridge.attr!(path, "name")  # Bang variant
```

### ref?/1

Check if a value is a Python object reference.

```elixir
{:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
SnakeBridge.ref?(path)            # => true
SnakeBridge.ref?("just a string") # => false
```

### bytes/1

Wrap binary data for explicit `bytes` encoding. Use when Python expects `bytes` (cryptography,
binary protocols, base64).

```elixir
{:ok, md5_ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
{:ok, hex} = SnakeBridge.method(md5_ref, "hexdigest", [])
# hex => "900150983cd24fb0d6963f7d28e17f72"

{:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])

# Binary round-trip
original = <<0, 1, 2, 127, 128, 255>>
{:ok, b64} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)])
{:ok, ^original} = SnakeBridge.call("base64", "b64decode", [b64])
```

## Runtime Options

Pass options via the `__runtime__:` key to control execution behavior.

```elixir
SnakeBridge.call("module", "function", [args],
  __runtime__: [
    session_id: "my_session",
    timeout: 30_000,
    affinity: :strict_queue,
    pool_name: :gpu_pool,
    idempotent: true
  ]
)
```

You can also set runtime defaults per process or scoped block:

```elixir
SnakeBridge.RuntimeContext.put_defaults(pool_name: :gpu_pool, timeout_profile: :ml_inference)

SnakeBridge.with_runtime(pool_name: :gpu_pool) do
  SnakeBridge.call("numpy", "mean", [scores])
end
```

### session_id

Use a specific session instead of the auto-session. Sessions isolate Python object refs.

```elixir
SnakeBridge.call("numpy", "array", [[1, 2, 3]], __runtime__: [session_id: "shared"])
```

### timeout

Call timeout in milliseconds. Default is pool-configured (typically 30 seconds).

```elixir
SnakeBridge.call("heavy_module", "compute", [data], __runtime__: [timeout: 120_000])
```

### affinity

Worker selection mode. See [Session Affinity](SESSION_AFFINITY.md) for details.

- `:hint` (default) - Best-effort routing; may use different worker if busy
- `:strict_queue` - Queue until preferred worker is available
- `:strict_fail_fast` - Return `{:error, :worker_busy}` if preferred is busy

```elixir
SnakeBridge.method(ref, "compute", [], __runtime__: [affinity: :strict_queue])
```

### pool_name

Target a specific worker pool in multi-pool configurations.

```elixir
SnakeBridge.call("torch", "tensor", [data], __runtime__: [pool_name: :gpu_pool])
```

### idempotent

Mark call as cacheable for response caching.

```elixir
SnakeBridge.get("numpy", "__version__", __runtime__: [idempotent: true])
```

## Helper Functions

### call_helper/3

Call custom Python helper functions from `priv/python/helpers/`.

```elixir
{:ok, result} = SnakeBridge.call_helper("my_helpers.process_data", [input], timeout: 5000)
```

Place helper modules in `priv/python/helpers/` and call by dotted path.

## When to Use Universal FFI vs Generated Wrappers

| Scenario | Recommendation |
|----------|----------------|
| Core library (NumPy, Pandas) | Generated wrappers |
| One-off stdlib call | Universal FFI |
| Runtime-determined module | Universal FFI |
| IDE autocomplete needed | Generated wrappers |
| Quick prototyping | Universal FFI |
| Plugin architecture | Universal FFI |

Both coexist in the same project:

```elixir
result = Numpy.mean(data)  # Generated wrapper
{:ok, hash} = SnakeBridge.call("hashlib", "sha256", [SnakeBridge.bytes(data)])  # Universal FFI
```

## Examples

### Working with Python Objects

```elixir
{:ok, pattern} = SnakeBridge.call("re", "compile", ["^\\d{3}-\\d{4}$"])
{:ok, match} = SnakeBridge.method(pattern, "match", ["555-1234"])  # ref if matched
{:ok, nil} = SnakeBridge.method(pattern, "match", ["invalid"])     # nil if no match
```

### Session Management

```elixir
{:ok, _} = SnakeBridge.call("math", "sqrt", [16])
session = SnakeBridge.current_session()  # => "auto_<0.123.0>_..."

# All refs in this process share the session
{:ok, ref1} = SnakeBridge.call("pathlib", "Path", ["."])
{:ok, ref2} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
ref1.session_id == ref2.session_id  # => true

:ok = SnakeBridge.release_auto_session()  # Cleanup when done
```

### Non-String Key Maps

```elixir
int_map = %{1 => "one", 2 => "two", 3 => "three"}
{:ok, result} = SnakeBridge.call("builtins", "dict", [int_map])

coord_map = %{{0, 0} => "origin", {1, 0} => "x-axis"}
{:ok, dict_ref} = SnakeBridge.call("builtins", "dict", [coord_map])
{:ok, "origin"} = SnakeBridge.method(dict_ref, "get", [{0, 0}])
```

### Streaming (Convert to List)

```elixir
{:ok, range_ref} = SnakeBridge.call("builtins", "range", [10])
{:ok, items} = SnakeBridge.call("builtins", "list", [range_ref])
# items => [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

Enum.sum(items)  # => 45
```

### Error Handling

```elixir
case SnakeBridge.call("nonexistent_module", "fn", []) do
  {:ok, result} -> process(result)
  {:error, reason} -> Logger.error("Failed: #{inspect(reason)}")
end

# Or with bang variants
try do
  SnakeBridge.call!("nonexistent_module", "fn", [])
rescue
  e in RuntimeError -> Logger.error("Caught: #{e.message}")
end
```

## See Also

- [Session Affinity](SESSION_AFFINITY.md) - Worker routing and affinity modes
- [Generated Wrappers](GENERATED_WRAPPERS.md) - Compile-time code generation
- [Refs and Sessions](REFS_AND_SESSIONS.md) - Python object lifecycle
