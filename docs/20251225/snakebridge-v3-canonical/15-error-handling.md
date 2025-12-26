# Error Handling

This document defines error categories and how they surface at each phase.

## Compile-Time Errors (Prepass)

### Scanner

- **SyntaxError** in source file → warning + skip file
- **Missing file** → skip
- **Unsupported AST** → skip

In `strict: true`, scanner errors become compiler diagnostics.

### Introspector

- `:uv_not_found` → error with install guidance
- `:python_not_found` → error with install guidance
- Import error (module not installed) → error
- Timeout → error with hint to increase timeout
- Function missing → warning (skipped)

Introspection errors during generation **fail compilation** unless `strict: false` and the symbol is optional.

### Generator

- File write failures (permission, disk full) → compilation error
- Name collisions → compilation error with override suggestion
- Docstring parse errors → sanitize and continue

### Manifest / Lock

- Lockfile mismatch → compilation error with `mix snakebridge.lock --rebuild` guidance
- Manifest/source mismatch → error with `mix snakebridge.verify` or `mix snakebridge.repair`

## Runtime Errors

### Snakepit Errors

Snakepit can return:

- `:pool_error` (no workers, queue full)
- `:timeout`
- `:grpc_error`

These are wrapped into `SnakeBridge.Error` with `type: :runtime_error`.

### Python Exceptions

Python exceptions are returned as structured errors:

```elixir
%SnakeBridge.Error{
  type: :python_error,
  python_type: "TypeError",
  message: "Invalid input",
  traceback: "...",
  suggestions: ["Check input shape", "Use Numpy.array/1"]
}
```

## Error Struct

```elixir
defmodule SnakeBridge.Error do
  @type t :: %__MODULE__{
    type: :python_error | :runtime_error | :generation_error | :config_error,
    message: String.t(),
    python_type: String.t() | nil,
    traceback: String.t() | nil,
    suggestions: [String.t()]
  }

  defstruct [:type, :message, :python_type, :traceback, suggestions: []]
end
```

## Error Surfaces

- **Compile time**: `Mix.Task.Compiler.Diagnostic` errors
- **Runtime**: `{:error, SnakeBridge.Error.t()}` tuples
- **CLI**: non-zero exit codes with human-readable diagnostics

## Recovery Paths

- **Missing adapters** → run `mix snakebridge.generate` and commit
- **Ledger entries** → run `mix snakebridge.promote`
- **Lock mismatch** → run `mix snakebridge.lock --rebuild`
- **Python/uv missing** → install and rerun `mix snakebridge.doctor`

