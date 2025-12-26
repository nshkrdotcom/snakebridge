# Error Handling

This document defines error categories and how they surface at each phase. SnakeBridge
owns compile-time errors; runtime errors come from Snakepit Prime and are passed through.

## Compile-Time Errors (Prepass)

### Scanner

- **SyntaxError** in source file → warning + skip file
- **Missing file** → skip
- **Unsupported AST** → skip

In `strict: true`, scanner errors become compiler diagnostics.

### Introspector

- Missing Python/uv/runtime → error with install guidance (from Snakepit)
- Import error (module not installed) → error
- Timeout → error with hint to increase timeout
- Function missing → warning (skipped)

Introspection errors during generation **fail compilation** unless `strict: false`
and the symbol is optional.

### Generator

- File write failures (permission, disk full) → compilation error
- Name collisions → compilation error with override suggestion
- Docstring parse errors → sanitize and continue

### Manifest / Lock

- Lockfile mismatch → compilation error with `mix snakebridge.lock --rebuild`
- Manifest/source mismatch → error with `mix snakebridge.verify` or `mix snakebridge.repair`

## Runtime Errors (Snakepit)

Snakepit Prime handles runtime execution and returns structured errors. SnakeBridge
passes these through unchanged.

Common categories:

- `:pool_error` (no workers, queue full)
- `:timeout`
- `:grpc_error`
- `:worker_crash` (segfault, CUDA fatal error)

Python exceptions surface as structured errors:

```elixir
{:error, %Snakepit.Error{
  type: :python_error,
  python_type: "TypeError",
  message: "Invalid input",
  traceback: "...",
  suggestions: ["Check input shape", "Use Numpy.array/1"]
}}
```

When a mapping exists, exceptions are promoted to specific structs for pattern
matching (defined in Snakepit):

```elixir
{:error, %Snakepit.Error.ValueError{
  message: "shapes (3,4) and (2,2) not aligned",
  stacktrace: [...],
  context: %{shape_a: [3,4], shape_b: [2,2]}
}}
```

## Error Surfaces

- **Compile time**: `Mix.Task.Compiler.Diagnostic` errors
- **Runtime**: `{:error, Snakepit.Error.t()}` tuples
- **CLI**: non-zero exit codes with human-readable diagnostics

## Recovery Paths

- **Missing adapters** → run `mix snakebridge.generate` and commit
- **Ledger entries** → run `mix snakebridge.promote`
- **Lock mismatch** → run `mix snakebridge.lock --rebuild`
- **Python/uv missing** → install and rerun `mix snakebridge.doctor`
