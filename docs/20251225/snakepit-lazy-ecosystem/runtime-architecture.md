# Runtime Architecture: Snakepit as the Substrate

This document defines how runtime behavior becomes transparent to users while remaining configurable for advanced teams.

## Core Principle

Snakepit starts automatically and is invisible to the developer by default. Users should not manually configure worker pools or Python paths for basic usage.

## Startup Sequence

1. Application boots.
2. Snakepit checks `snakebridge` config for libraries.
3. Python environment is created or reused.
4. Workers are started with the correct library set.
5. Generated adapters call `Snakepit.execute/3`.

## Runtime API

Generated wrappers are thin:

```
@spec sqrt(number()) :: number()
@doc "Return the square root of x."

def sqrt(x) do
  __python_call__("sqrt", [x])
end
```

`__python_call__` resolves to a Snakepit client call that uses the current library context.

## Pooling and Performance

- Pooling is configurable but defaulted to a safe, minimal setting.
- Worker concurrency is tuned for CPU-bound libraries.
- Thread limits are set for common scientific stacks.

## Error Surface

Errors should be Elixir-friendly:

- Python exceptions mapped to Elixir structs
- Callsite context preserved
- Guidance included (library missing, version mismatch, etc)

## Advanced Configuration

For teams that need it:

- Pool size, worker concurrency, and timeouts
- GPU visibility and CUDA libraries
- Per-library worker pools

## Security and Isolation

- Optional sandboxed worker mode for untrusted code
- Strict dependency pinning for production
- Hash-based validation of metadata and adapters

