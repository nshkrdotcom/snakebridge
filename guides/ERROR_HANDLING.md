# Error Handling

SnakeBridge provides a structured error system that translates Python exceptions into
typed Elixir errors, enabling pattern matching and actionable suggestions.

## Error Structure Types

### ShapeMismatchError

For tensor/array shape incompatibilities:

```elixir
%SnakeBridge.Error.ShapeMismatchError{
  operation: :matmul,           # :matmul, :broadcast, :elementwise, :index
  shape_a: [3, 4],
  shape_b: [5, 6],
  message: "shapes cannot be multiplied (3x4 and 5x6)",
  suggestion: "For matrix multiplication, A columns (4) must equal B rows (5)...",
  python_traceback: "..."
}
```

### OutOfMemoryError

For GPU/CPU memory exhaustion:

```elixir
%SnakeBridge.Error.OutOfMemoryError{
  device: {:cuda, 0},           # {:cuda, N}, :mps, :cpu
  requested_mb: 8192,
  available_mb: 2048,
  total_mb: 24576,
  message: "CUDA out of memory",
  suggestions: ["Reduce batch size", "Use gradient checkpointing", ...],
  python_traceback: "..."
}
```

### DtypeMismatchError

For tensor dtype incompatibilities:

```elixir
%SnakeBridge.Error.DtypeMismatchError{
  expected: :float32,
  got: :float64,
  operation: :matmul,
  message: "expected scalar type Float but found Double",
  suggestion: "Convert with tensor.to(torch.float32)",
  python_traceback: "..."
}
```

### Reference Errors

For ref lifecycle issues:

```elixir
# Ref no longer exists
%SnakeBridge.RefNotFoundError{ref_id: "abc123", session_id: "session_456", message: "..."}

# Ref used in wrong session
%SnakeBridge.SessionMismatchError{
  ref_id: "abc123", expected_session: "session_A", actual_session: "session_B"
}

# Malformed ref payload
%SnakeBridge.InvalidRefError{reason: :missing_id, message: "..."}
```

## Error Modes Configuration

Configure via application config:

```elixir
config :snakebridge, error_mode: :raw  # default
```

### :raw (Default)

Returns the original error payload:

```elixir
{:error, %{message: "shapes cannot be multiplied", python_type: "RuntimeError", ...}}
```

### :translated

Applies `ErrorTranslator` to all errors:

```elixir
case SnakeBridge.call("torch", "matmul", [a, b]) do
  {:ok, result} -> result
  {:error, %SnakeBridge.Error.ShapeMismatchError{} = e} ->
    Logger.error("Shape error: #{e.suggestion}")
end
```

### :raise_translated

Raises translated errors for use with `call!/4`:

```elixir
try do
  SnakeBridge.call!("torch", "matmul", [a, b])
rescue
  e in SnakeBridge.Error.ShapeMismatchError -> IO.puts("Shape: #{e.suggestion}")
  e in SnakeBridge.Error.OutOfMemoryError -> IO.puts("OOM on #{inspect(e.device)}")
end
```

## ErrorTranslator

The `SnakeBridge.ErrorTranslator` module detects patterns and converts errors.

### Detection Patterns

**Shape errors:** `shapes cannot be multiplied`, `size of tensor`, `incompatible shapes`,
`Dimension out of range`, `shape mismatch`

**OOM errors:** `out of memory`, `OutOfMemory`, `OOM` (detects CUDA/MPS/CPU device)

**Dtype errors:** `expected scalar type X but found Y`, `expected dtype torch.X but got torch.Y`

**Ref errors:** `Unknown SnakeBridge reference`, `SnakeBridge reference session mismatch`,
`Invalid SnakeBridge reference`

### Manual Translation

```elixir
alias SnakeBridge.ErrorTranslator

error = %RuntimeError{message: "CUDA out of memory. Tried to allocate 8192 MiB"}
translated = ErrorTranslator.translate(error)
# => %SnakeBridge.Error.OutOfMemoryError{device: {:cuda, 0}, ...}

ErrorTranslator.dtype_from_string("Float")         # => :float32
ErrorTranslator.dtype_from_string("torch.float64") # => :float64
```

## Error Flow

```
Python Exception
      |
encode_error() + traceback.format_exc()   [Python side]
      |
JSON over gRPC to Elixir
      |
SnakeBridge.Runtime receives {:error, payload}
      |
apply_error_mode() --> :raw         --> {:error, payload}
                   --> :translated  --> {:error, structured_error}
                   --> :raise_translated --> raise structured_error
```

## Python Error Encoding

Exceptions are encoded with type and traceback:

```python
def encode_error(exception: Exception) -> dict:
    return {
        "success": False,
        "error": str(exception),
        "error_type": type(exception).__name__
    }
```

Tracebacks captured via `traceback.format_exc()`.

## Dynamic Exceptions

For Python types without specialized structs, SnakeBridge creates modules at runtime.

### get_or_create_module

```elixir
alias SnakeBridge.DynamicException

ValueError = DynamicException.get_or_create_module("ValueError")
# => SnakeBridge.DynamicException.ValueError

error = DynamicException.create("ValueError", "invalid literal for int()")
# => %SnakeBridge.DynamicException.ValueError{message: "...", python_class: "ValueError"}
```

### Rescuing Dynamic Exceptions

```elixir
try do
  SnakeBridge.call!("json", "loads", ["invalid"])
rescue
  e in SnakeBridge.DynamicException.JSONDecodeError ->
    IO.puts("JSON error: #{e.message}")
end
```

Fields: `message`, `python_class`, `details`, `python_traceback`

## Best Practices

### Choose Error Mode by Environment

- Development: `:translated` for readable errors
- Production with custom handling: `:raw`
- Production with exceptions: `:raise_translated`

### Pattern Match for Recovery

```elixir
case SnakeBridge.call("torch", "matmul", [a, b]) do
  {:ok, result} -> result

  {:error, %ShapeMismatchError{}} ->
    b_t = SnakeBridge.call!("torch", "transpose", [b, 0, 1])
    SnakeBridge.call("torch", "matmul", [a, b_t])

  {:error, %OutOfMemoryError{device: {:cuda, _}}} ->
    SnakeBridge.call("torch", "matmul", [a, b], __runtime__: [device: :cpu])
end
```

### Handle Ref Lifecycle Errors

```elixir
case SnakeBridge.method(ref, "predict", [input]) do
  {:ok, result} -> result
  {:error, %RefNotFoundError{}} ->
    new_ref = SnakeBridge.call!("model", "load", [path])
    SnakeBridge.method!(new_ref, "predict", [input])
  {:error, %SessionMismatchError{}} ->
    Logger.error("Cross-session ref usage")
    {:error, :invalid_state}
end
```

### Log Tracebacks and Use Suggestions

Structured errors preserve the Python traceback (`python_traceback` field) and include
actionable suggestions (`suggestion`/`suggestions` fields) for user feedback.

## See Also

- [Refs and Sessions](REFS_AND_SESSIONS.md) - Ref lifecycle
- [Type System](TYPE_SYSTEM.md) - Serialization details
- [Best Practices](BEST_PRACTICES.md) - Patterns and recommendations
