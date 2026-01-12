# Refs and Sessions

SnakeBridge uses refs to represent Python objects in Elixir and sessions to manage
their lifecycle. Understanding these concepts is essential for building stateful
applications that interact with Python.

## Understanding Refs

A ref is a structured reference to a Python object stored in the Python-side registry.
Instead of serializing complex Python objects directly, SnakeBridge keeps them in
Python memory and passes a lightweight reference to Elixir.

### When Are Refs Created?

Refs are created automatically when a Python function returns a non-serializable value:

```elixir
# Compiled regex pattern - not JSON-serializable, becomes a ref
{:ok, pattern} = SnakeBridge.call("re", "compile", ["\\d+"])
# pattern is a %SnakeBridge.Ref{}

# Simple return values are passed directly
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])
# result is 4.0 (float)
```

### Ref Structure

The `SnakeBridge.Ref` struct contains:

```elixir
%SnakeBridge.Ref{
  id: "abc123def456",        # Unique identifier (UUID hex)
  session_id: "auto_12345",  # Session this ref belongs to
  pool_name: :main,          # Optional pool affinity
  python_module: "re",       # Source Python module
  library: "stdlib",         # Library name
  type_name: "Pattern",      # Python type name
  schema: 1                  # Wire format version
}
```

### Wire Format

Refs are transmitted between Elixir and Python as tagged JSON:

```json
{
  "__type__": "ref",
  "__schema__": 1,
  "id": "abc123def456",
  "session_id": "auto_12345",
  "type_name": "Pattern",
  "python_module": "re"
}
```

When you pass a ref back to Python (via `method/4` or `attr/3`), SnakeBridge
converts it to this wire format and looks up the actual Python object by
`{session_id}:{ref_id}` in the registry.

## Ref Operations

### Checking for Refs

Use `ref?/1` to determine if a value is a ref:

```elixir
{:ok, pattern} = SnakeBridge.call("re", "compile", ["\\d+"])
SnakeBridge.ref?(pattern)  # true

{:ok, result} = SnakeBridge.call("math", "sqrt", [16])
SnakeBridge.ref?(result)   # false (it's a float)
```

### Calling Methods

Use `method/4` to call methods on a ref:

```elixir
{:ok, pattern} = SnakeBridge.call("re", "compile", ["\\d+"])

# Call the match method
{:ok, match} = SnakeBridge.method(pattern, "match", ["123abc"])

# Bang variant raises on error
match = SnakeBridge.method!(pattern, "match", ["123abc"])
```

### Accessing Attributes

Use `attr/3` to read object attributes:

```elixir
{:ok, pattern} = SnakeBridge.call("re", "compile", ["\\d+"])

# Get the pattern string
{:ok, pattern_str} = SnakeBridge.attr(pattern, "pattern")
# pattern_str is "\\d+"

# Bang variant
pattern_str = SnakeBridge.attr!(pattern, "pattern")
```

### Releasing Refs

Explicitly release refs when you no longer need them:

```elixir
{:ok, large_model} = SnakeBridge.call("transformers", "AutoModel.from_pretrained", ["gpt2"])

# Use the model...

# Release when done to free Python memory
SnakeBridge.release_ref(large_model)
```

Releasing is optional for short-lived refs since sessions clean up automatically.
However, for large objects like ML models, explicit release prevents memory buildup.

## Session Types

Sessions group refs for lifecycle management. All refs belong to exactly one session.

### Auto-Sessions (Process-Scoped)

By default, SnakeBridge creates an auto-session for each Elixir process:

```elixir
# First call creates an auto-session
{:ok, _} = SnakeBridge.call("math", "sqrt", [16])

# Get the current session ID
session = SnakeBridge.current_session()  # "auto_123456..."

# All calls in the same process share the session
{:ok, ref1} = SnakeBridge.call("re", "compile", ["\\d+"])
{:ok, ref2} = SnakeBridge.call("re", "compile", ["\\w+"])
ref1.session_id == ref2.session_id  # true
```

Auto-sessions are convenient and require no configuration. The session is released
when the owning process terminates.

### Explicit Sessions

Use `SessionContext.with_session/2` for custom session IDs:

```elixir
alias SnakeBridge.SessionContext

SessionContext.with_session([session_id: "my_session"], fn ->
  {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
  # ref.session_id == "my_session"
end)
```

Explicit sessions are useful when you need:
- Cross-process ref sharing
- Predictable session IDs for debugging
- Fine-grained lifecycle control

### Named Sessions (Cross-Process)

Share refs across processes by using the same explicit session ID:

```elixir
# Process A - create a shared model
session_id = "model_session_#{System.unique_integer()}"

SessionContext.with_session([session_id: session_id], fn ->
  {:ok, model} = SnakeBridge.call("sklearn.linear_model", "LinearRegression", [])
  send(process_b, {:model, session_id, model})
end)

# Process B - use the shared model
receive do
  {:model, session_id, model} ->
    SessionContext.with_session([session_id: session_id], fn ->
      {:ok, predictions} = SnakeBridge.method(model, "predict", [test_data])
    end)
end
```

Note: Cross-process sharing requires strict session affinity to ensure refs route
to the correct Python worker. See the [Session Affinity](SESSION_AFFINITY.md) guide.

## Session Lifecycle

### Creation

Sessions are created on the first Python call:

1. Elixir resolves the session ID (auto-generated or explicit)
2. The call includes the session ID in the request
3. Python creates the registry entry if it does not exist

### Ref Storage

Python stores objects in a dictionary keyed by `{session_id}:{ref_id}`:

```python
_instance_registry["my_session:abc123"] = {
    "obj": <Pattern object>,
    "created_at": 1704931200.0,
    "last_access": 1704931250.0
}
```

### Cleanup Triggers

Sessions and their refs are cleaned up when:

1. **Manual release**: Call `SnakeBridge.release_session(session_id)`
2. **Process exit**: When the owner process terminates (auto-sessions)
3. **TTL expiration**: If TTL is configured and refs exceed it
4. **Registry overflow**: Oldest refs are evicted when the registry is full

## TTL Configuration

Configure ref time-to-live to prevent memory leaks in long-running processes:

```elixir
# config/config.exs
config :snakebridge,
  ref_ttl: 3600,              # Refs expire after 1 hour (seconds)
  session_max_refs: 10_000    # Max refs per session
```

Or via environment variables: `SNAKEBRIDGE_REF_TTL_SECONDS` and `SNAKEBRIDGE_REF_MAX`.

`SessionContext.with_session/2` applies defaults of `ttl_seconds: 3600` and
`max_refs: 10_000`. Override per session:

```elixir
SessionContext.with_session([
  session_id: "long_running",
  ttl_seconds: 86400,    # 24 hours
  max_refs: 50_000
], fn ->
  # Long-running work
end)
```

## Python-Side Registry

The registry lives in `priv/python/snakebridge_adapter.py`:

```python
_instance_registry: Dict[str, Any] = {}  # {session_id}:{ref_id} -> entry
_registry_lock = threading.RLock()       # Thread-safe access
```

Each entry stores `{"obj": <Python object>, "created_at": timestamp, "last_access": timestamp}`.
The `last_access` timestamp updates on each access, supporting LRU eviction.

Key operations: `_store_ref(key, obj)`, `_get_ref(key)`, `_delete_ref(key)`, and
`_prune_registry()` which removes expired refs (TTL) and evicts oldest refs when
the registry exceeds max size.

## Error Types

### RefNotFoundError

Raised when a ref no longer exists in the registry:

```elixir
# Causes:
# - Ref was released via release_ref/1
# - Session was released via release_session/1
# - TTL expired
# - Evicted due to registry size limits

{:error, %SnakeBridge.RefNotFoundError{
  ref_id: "abc123",
  session_id: "my_session",
  message: "SnakeBridge reference 'abc123' not found in session 'my_session'..."
}}
```

### SessionMismatchError

Raised when a ref is used in a different session than it was created in:

```elixir
# ref_from_session_a used in session B
{:error, %SnakeBridge.SessionMismatchError{
  ref_id: "abc123",
  expected_session: "session_a",
  actual_session: "session_b",
  message: "SnakeBridge reference 'abc123' belongs to session 'session_a'..."
}}
```

This error often indicates a bug where refs are being shared without proper
session coordination.

### InvalidRefError

Raised when the ref payload is malformed:

```elixir
# Causes:
# - Missing 'id' field
# - Missing '__type__' field
# - Unrecognized format

{:error, %SnakeBridge.InvalidRefError{
  reason: :missing_id,
  message: "Invalid SnakeBridge reference: missing 'id' field"
}}
```

## Best Practices

### Use Auto-Sessions for Most Cases

Auto-sessions handle lifecycle automatically and work well for request-scoped work:

```elixir
def handle_request(data) do
  {:ok, result} = SnakeBridge.call("processor", "process", [data])
  # Refs cleaned up when request process exits
  result
end
```

### Release Large Objects Explicitly

For memory-intensive objects, release immediately after use:

```elixir
{:ok, model} = SnakeBridge.call("torch", "load", [model_path])
predictions = SnakeBridge.method!(model, "predict", [inputs])
SnakeBridge.release_ref(model)  # Free memory now
predictions
```

### Configure TTL for Long-Running Processes

GenServers and other long-lived processes can accumulate refs:

```elixir
# In config.exs
config :snakebridge, ref_ttl: 3600
```

### Use Explicit Sessions for Cross-Process Sharing

Always use the same session ID when sharing refs across processes.

### Handle Ref Errors Gracefully

Refs can become invalid between creation and use:

```elixir
case SnakeBridge.method(ref, "predict", [data]) do
  {:ok, result} -> {:ok, result}
  {:error, %SnakeBridge.RefNotFoundError{}} -> {:error, :ref_expired}
  {:error, reason} -> {:error, reason}
end
```

## See Also

- [Session Affinity](SESSION_AFFINITY.md) - Worker routing for session-scoped calls
- [Streaming](STREAMING.md) - StreamRef for Python generators
- [Error Handling](ERROR_HANDLING.md) - Complete error reference