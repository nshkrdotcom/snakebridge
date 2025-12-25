# Lazy Generation Engine

This document describes how Snakepit + Snakebridge generate adapters only for the symbols your code actually uses.

## The Goal

Generate the smallest possible adapter surface that still preserves compile-time tooling benefits.

## Inputs

- `libraries` list from `mix.exs`
- Introspection metadata for each library (functions, classes, docstrings, signatures)
- Project AST (Elixir source) to detect usage
- Optional runtime usage ledger for dynamic calls

## Output

- Stable, minimal Elixir modules under `lib/snakebridge_generated/`
- A usage ledger per library
- A manifest that tracks what has been generated

## Compile-Time Detection

### 1. AST Scan

During `mix compile`, Snakebridge scans project files to find call sites:

- `Sympy.sqrt(x)`
- `Sympy.Matrix(...)`
- `Sympy.JSONDecodeError.message()`

The scanner maps module aliases and imports so it can resolve `Sympy` to `Snakebridge.Sympy` or a library alias.

### 2. Symbol Resolution

For each detected call, the scanner resolves the symbol from the introspection metadata:

- If the symbol exists in metadata, it is queued for generation.
- If the symbol is missing, it is recorded for diagnostics.

### 3. Incremental Generation

The generator merges new symbols with the existing manifest and writes new or updated modules. Symbols are appended, never removed.

## Runtime Detection (Optional)

Dynamic calls are common in AI systems (for example, `apply(module, fun, args)`). For these cases:

- The runtime provides `Snakepit.dynamic_call/4`
- Every successful dynamic call is recorded in a usage ledger
- The next compile will generate wrappers for those calls

This keeps compile-time adapters accurate without sacrificing dynamic flexibility.

## Manifest Format

Each library has a manifest that records generated symbols and their source metadata:

```
{
  "library": "sympy",
  "version": "1.12",
  "generated_at": "2025-12-25T12:00:00Z",
  "symbols": {
    "functions": ["sqrt/1", "expand/2"],
    "classes": ["Matrix", "Symbol"]
  }
}
```

## Build Flow

```
Project Compile
  -> AST Scan
  -> Resolve symbols via metadata
  -> Compare to manifest
  -> Generate missing adapters
  -> Update manifest and usage ledger
```

## Why This Works

- The adapter surface is always as small as possible.
- The surface only grows when the project grows.
- Build times stay proportional to actual usage.

