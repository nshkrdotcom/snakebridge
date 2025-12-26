# Runtime Integration (Snakepit Prime Contract)

## Overview

SnakeBridge generates Elixir wrappers, but **execution happens in Snakepit Prime**.
This document defines the payload contract SnakeBridge must emit. Runtime behavior
(pooling, crash barrier, zero-copy, exception translation) is owned by Snakepit.

Assumption: Snakepit Prime runtime (>= 0.7.(x+1)) is available and configured.

## Tool Names

SnakeBridge-generated wrappers call these Snakepit tools:

- `snakebridge.call` (request/response)
- `snakebridge.stream` (streaming)

If you provide a custom adapter, it must expose these tool names.

## Base Payload

```json
{
  "library": "numpy",
  "python_module": "numpy.linalg",
  "function": "solve",
  "args": ["..."],
  "kwargs": {"axis": 0},
  "idempotent": true
}
```

### Fields

- `library`: top-level library name
- `python_module`: dotted module path for submodules
- `function`: function/method name
- `args`: positional args (may include `Snakepit.ZeroCopyRef` handles)
- `kwargs`: keyword args
- `idempotent`: used by Snakepit crash barrier retry policy

## Class and Method Payloads

```json
{
  "call_type": "class",
  "library": "sympy",
  "python_module": "sympy",
  "class": "Symbol",
  "function": "__init__",
  "args": ["x"],
  "kwargs": {}
}
```

```json
{
  "call_type": "method",
  "library": "sympy",
  "python_module": "sympy",
  "instance": "<pyref>",
  "function": "simplify",
  "args": [],
  "kwargs": {}
}
```

```json
{
  "call_type": "get_attr",
  "library": "sympy",
  "python_module": "sympy",
  "instance": "<pyref>",
  "attr": "name"
}
```

## Runtime Client Helper

Generated wrappers call a small helper that builds payloads and delegates to
Snakepit. This helper is not a runtime subsystem; it exists to keep payload
construction consistent and to allow test stubs.

```elixir
SnakeBridge.Runtime.call(Numpy, :mean, [arr], opts)
# -> Snakepit.execute("snakebridge.call", payload)
```

You may override the client module in tests (see `08-developer-experience.md`).

```elixir
config :snakebridge, runtime_client: MyApp.SnakepitStub
```

## Sessions and PyRef

Python object references are session-bound. For instance methods, use sessions:

```elixir
Snakepit.execute_in_session(session_id, "snakebridge.call", payload)
```

## Runtime Features (Owned by Snakepit)

- **Zero-copy interop**: `Snakepit.ZeroCopyRef` handles pass through payloads.
- **Crash barrier**: `idempotent` enables safe retries when workers crash.
- **Exception translation**: errors surface as `Snakepit.Error` structs.
- **Hermetic Python**: runtime identity is managed by Snakepit.

SnakeBridge only guarantees that payloads include the fields required for these
features. For details, see the Snakepit Prime runtime docs.
