# Runtime Integration (Snakepit Contract)

## Overview

SnakeBridge generates Elixir wrappers, but **execution happens in Snakepit**. This document specifies the runtime contract between generated code and Snakepit.

## Required Snakepit Configuration

```elixir
# config/config.exs
config :snakepit,
  pooling_enabled: true,
  adapter_module: Snakepit.Adapters.GRPCPython,
  adapter_args: ["--adapter", "snakebridge_adapter"]
```

SnakeBridge ships a Python adapter named `snakebridge_adapter` that exposes two tools:

- `snakebridge.call` (request/response)
- `snakebridge.stream` (streaming)

## Runtime API

### Standard Call

```elixir
@spec call(module(), atom(), list(), keyword()) :: {:ok, term()} | {:error, SnakeBridge.Error.t()}
def call(module, function, args, kwargs \\ []) do
  Snakepit.execute("snakebridge.call", %{
    library: library_name(module),           # "numpy" or "sympy"
    python_module: python_name(module),      # "numpy" or "numpy.linalg"
    function: to_string(function),
    args: args,
    kwargs: Map.new(kwargs)
  })
end
```

`python_name/1` reads `__snakebridge_python_name__/0` from generated modules. Top-level libraries return `"numpy"`, nested submodules return `"numpy.linalg"`.

### Session-Affine Call

Python object references are only valid in the worker that created them. Use sessions for methods on `SnakeBridge.PyRef.t()`:

```elixir
@spec call_in_session(String.t(), module(), atom(), list(), keyword()) :: {:ok, term()} | {:error, SnakeBridge.Error.t()}
def call_in_session(session_id, module, function, args, kwargs \\ []) do
  Snakepit.execute_in_session(session_id, "snakebridge.call", %{
    library: library_name(module),
    python_module: python_name(module),
    function: to_string(function),
    args: args,
    kwargs: Map.new(kwargs)
  })
end
```

### Streaming Call

```elixir
@spec stream(module(), atom(), list(), keyword(), (map() -> any())) :: :ok | {:error, SnakeBridge.Error.t()}
def stream(module, function, args, kwargs \\ [], on_chunk) do
  Snakepit.execute_stream("snakebridge.stream", %{
    library: library_name(module),
    python_module: python_name(module),
    function: to_string(function),
    args: args,
    kwargs: Map.new(kwargs)
  }, on_chunk)
end
```

## Class and Method Calls

Class and instance operations use the same `snakebridge.call` tool with a `call_type` field:

```elixir
# Constructor
%{call_type: "class", library: "sympy", python_module: "sympy", class: "Symbol", function: "__init__", args: [...], kwargs: %{...}}

# Instance method
%{call_type: "method", library: "sympy", python_module: "sympy", instance: ref, function: "simplify", args: [...], kwargs: %{...}}

# Attribute access
%{call_type: "get_attr", library: "sympy", python_module: "sympy", instance: ref, attr: "name"}
%{call_type: "set_attr", library: "sympy", python_module: "sympy", instance: ref, attr: "name", value: "x"}
```

The Python adapter resolves these call types and invokes the correct Python object.

### Convenience Helpers

Generated code calls helper functions to construct the appropriate payloads:

```elixir
SnakeBridge.Runtime.call_class(Sympy.Symbol, :__init__, [name], opts)
SnakeBridge.Runtime.call_method(ref, :simplify, [], opts)
SnakeBridge.Runtime.get_attr(ref, :name)
SnakeBridge.Runtime.set_attr(ref, :name, "x")
```

## Serialization

Snakepit handles serialization to/from Python. SnakeBridge assumes:

- Primitives are JSON-compatible
- Complex objects are returned as `SnakeBridge.PyRef.t()` handles
- Errors are returned in a structured error format (see `15-error-handling.md`)

## Dynamic Calls and Ledger

For dynamic dispatch (`apply/3`), use the runtime helper so calls are recorded:

```elixir
SnakeBridge.Runtime.dynamic_call(Numpy, :custom_op, [a, b, c])
```

In dev, dynamic calls are written to the ledger and can be promoted with `mix snakebridge.promote`.

## Timeouts and Pooling

Per-call timeouts and pool selection are delegated to Snakepit configuration. SnakeBridge does not manage pool scheduling.

For high-throughput or long-running tasks, configure Snakepit pools and use `execute_in_session/3` for affinity.
