# Runtime Integration Patterns

Status: Design
Date: 2025-12-25

## Overview

SnakeBridge generates compile-time bindings. Snakepit executes them at runtime.
This document clarifies the integration boundary and patterns for making them
work together seamlessly.

## The Boundary

```
┌─────────────────────────────────────────────────────────────┐
│                      COMPILE TIME                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SnakeBridge                             │   │
│  │  • Scan project for library calls                   │   │
│  │  • Introspect Python via Snakepit.PythonRuntime     │   │
│  │  • Generate .ex wrapper modules                     │   │
│  │  • Maintain manifest + lockfile                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Output: lib/snakebridge_generated/*.ex                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                        RUNTIME                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Snakepit                                │   │
│  │  • Manage Python worker pool                        │   │
│  │  • Execute tool calls via gRPC                      │   │
│  │  • Handle sessions, streaming, errors               │   │
│  │  • Provide crash barrier, telemetry                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Generated code calls: Snakepit.execute("snakebridge.call", ...) │
└─────────────────────────────────────────────────────────────┘
```

## Generated Code Pattern

Every generated function follows this pattern:

```elixir
# lib/snakebridge_generated/numpy.ex

defmodule Numpy do
  @moduledoc "SnakeBridge bindings for `numpy`."

  def __snakebridge_python_name__, do: "numpy"
  def __snakebridge_library__, do: "numpy"

  @doc "Create an array."
  @spec array(term(), keyword()) :: {:ok, term()} | {:error, Snakepit.Error.t()}
  def array(object, opts \\ []) do
    SnakeBridge.Runtime.call(__MODULE__, :array, [object], opts)
  end
end
```

The `SnakeBridge.Runtime.call/4` function builds a payload and delegates to Snakepit:

```elixir
# lib/snakebridge/runtime.ex

def call(module, function, args, opts \\ []) do
  python_module = module.__snakebridge_python_name__()
  library = module.__snakebridge_library__()

  payload = %{
    "library" => to_string(library),
    "python_module" => python_module,
    "function" => to_string(function),
    "args" => encode_args(args),
    "kwargs" => encode_kwargs(opts),
    "idempotent" => Keyword.get(opts, :idempotent, false)
  }

  runtime_client().execute("snakebridge.call", payload, opts)
end

defp runtime_client do
  Application.get_env(:snakebridge, :runtime_client, Snakepit)
end
```

## Snakepit Tool Contract

Snakepit must register a tool named `snakebridge.call` that:

1. Receives the payload above
2. Imports the Python module
3. Calls the function with args/kwargs
4. Returns encoded result or error

**Python-side tool implementation** (in Snakepit's adapter):

```python
# snakepit_bridge/tools/snakebridge_call.py

def snakebridge_call(payload, context):
    """Execute a SnakeBridge function call."""
    import importlib

    library = payload["library"]
    python_module = payload["python_module"]
    function = payload["function"]
    args = payload["args"]
    kwargs = payload["kwargs"]

    # Import module
    mod = importlib.import_module(python_module)

    # Get function
    fn = getattr(mod, function)

    # Call
    result = fn(*args, **kwargs)

    # Encode and return
    return serialize(result)
```

## Class and Method Patterns

### Class Instantiation

```elixir
# Generated
defmodule Json.Encoder.JSONEncoder do
  def new(arg, opts \\ []) do
    SnakeBridge.Runtime.call_class(__MODULE__, :__init__, [arg], opts)
  end
end
```

```elixir
# Runtime
def call_class(module, _init, args, opts) do
  payload = %{
    "call_type" => "class",
    "library" => module.__snakebridge_library__(),
    "python_module" => module.__snakebridge_python_module__(),
    "class" => module.__snakebridge_python_class__(),
    "args" => encode_args(args),
    "kwargs" => encode_kwargs(opts)
  }

  runtime_client().execute("snakebridge.call", payload, opts)
end
```

Result is a `Snakepit.PyRef` handle.

### Method Calls

```elixir
# User code
{:ok, encoder} = Json.Encoder.JSONEncoder.new(indent: 2)
{:ok, result} = SnakeBridge.call_method(encoder, :encode, [%{a: 1}])
```

```elixir
# Runtime
def call_method(ref, method, args, opts \\ []) do
  payload = %{
    "call_type" => "method",
    "ref" => ref.id,
    "method" => to_string(method),
    "args" => encode_args(args),
    "kwargs" => encode_kwargs(opts)
  }

  runtime_client().execute("snakebridge.call", payload, opts)
end
```

### Attribute Access

```elixir
# Get attribute
{:ok, value} = SnakeBridge.get_attr(encoder, :item_separator)

# Set attribute
:ok = SnakeBridge.set_attr(encoder, :item_separator, " : ")
```

## Streaming Pattern

For functions that yield results incrementally:

```elixir
# Generated (marked as streaming in config)
defmodule Torch do
  def generate_stream(prompt, opts \\ []) do
    callback = Keyword.fetch!(opts, :callback)
    SnakeBridge.Runtime.stream(__MODULE__, :generate_stream, [prompt], callback, opts)
  end
end
```

```elixir
# Runtime
def stream(module, function, args, callback, opts) do
  payload = %{
    "library" => module.__snakebridge_library__(),
    "python_module" => module.__snakebridge_python_name__(),
    "function" => to_string(function),
    "args" => encode_args(args),
    "kwargs" => encode_kwargs(opts),
    "streaming" => true
  }

  runtime_client().execute_stream("snakebridge.stream", payload, callback, opts)
end
```

The `callback` receives chunks:

```elixir
Torch.generate_stream("Hello", callback: fn
  {:chunk, token} -> IO.write(token)
  {:done, _} -> IO.puts("")
  {:error, err} -> IO.puts("Error: #{inspect(err)}")
end)
```

## Error Translation

Snakepit returns `{:error, %Snakepit.Error{}}`. SnakeBridge can wrap or enhance:

```elixir
# In runtime.ex
def call(module, function, args, opts) do
  case runtime_client().execute("snakebridge.call", payload, opts) do
    {:ok, result} ->
      {:ok, decode_result(result)}

    {:error, %Snakepit.Error{category: :python_error} = err} ->
      {:error, enhance_python_error(err, module, function, args)}

    {:error, err} ->
      {:error, err}
  end
end

defp enhance_python_error(err, module, function, args) do
  %{err |
    context: Map.merge(err.context || %{}, %{
      elixir_module: module,
      elixir_function: function,
      elixir_arity: length(args)
    })
  }
end
```

## Session Affinity

For stateful operations, use Snakepit sessions:

```elixir
# Start a session
{:ok, session} = Snakepit.create_session()

# All calls in session go to same worker
{:ok, model} = SnakeBridge.in_session(session, fn ->
  Torch.load("model.pt")
end)

# Session tracks the PyRef
{:ok, output} = SnakeBridge.in_session(session, fn ->
  Torch.forward(model, input)
end)

# Clean up
Snakepit.close_session(session)
```

Implementation:

```elixir
def in_session(session, fun) do
  Process.put(:snakebridge_session, session)
  try do
    fun.()
  after
    Process.delete(:snakebridge_session)
  end
end

# In runtime.ex
defp session_opts(opts) do
  case Process.get(:snakebridge_session) do
    nil -> opts
    session -> Keyword.put(opts, :session, session)
  end
end
```

## Type Encoding/Decoding

The existing `SnakeBridge.Types` module handles lossless encoding:

| Elixir Type | Wire Format | Notes |
|-------------|-------------|-------|
| `nil` | `null` | |
| `true/false` | `true/false` | |
| integer | number | |
| float | number | |
| string | string | UTF-8 |
| binary | `{"__type__": "binary", "data": "base64..."}` | |
| atom | `{"__type__": "atom", "value": "..."}` | |
| tuple | `{"__type__": "tuple", "elements": [...]}` | |
| map | object | Atom keys → strings |
| list | array | |
| MapSet | `{"__type__": "set", "elements": [...]}` | |
| DateTime | `{"__type__": "datetime", "value": "..."}` | ISO8601 |
| PyRef | `{"__type__": "ref", "id": "..."}` | Object handle |

## Runtime Client Abstraction

For testing, the runtime client is configurable:

```elixir
# In test/support/mocks.ex
Mox.defmock(SnakeBridge.MockRuntime, for: SnakeBridge.RuntimeClient)

# In test/my_test.exs
setup do
  Application.put_env(:snakebridge, :runtime_client, SnakeBridge.MockRuntime)
  on_exit(fn -> Application.delete_env(:snakebridge, :runtime_client) end)
end

test "numpy array call" do
  expect(SnakeBridge.MockRuntime, :execute, fn tool, payload, _opts ->
    assert tool == "snakebridge.call"
    assert payload["function"] == "array"
    {:ok, [1, 2, 3]}
  end)

  assert {:ok, [1, 2, 3]} = Numpy.array([1, 2, 3])
end
```

## Pool Configuration

Snakepit manages the worker pool. SnakeBridge doesn't configure it directly,
but users may want pool settings for SnakeBridge workloads:

```elixir
# config/config.exs
config :snakepit,
  pools: [
    %{
      name: :default,
      pool_size: 16,
      worker_profile: :process,
      adapter_module: Snakepit.Adapters.GRPCPython,
      adapter_args: ["--adapter", "snakepit_bridge.adapters.default.DefaultAdapter"]
    }
  ]
```

The SnakeBridge runtime uses the `:default` pool unless specified:

```elixir
# Use a different pool
Numpy.array([1, 2, 3], pool: :gpu_pool)
```

## Telemetry Integration

SnakeBridge emits telemetry events that integrate with Snakepit's telemetry:

```elixir
# Events emitted by SnakeBridge
[:snakebridge, :call, :start]
[:snakebridge, :call, :stop]
[:snakebridge, :call, :exception]

# Metadata includes
%{
  library: :numpy,
  module: Numpy,
  function: :array,
  arity: 1
}

# Measurements include
%{
  duration: 1234,  # microseconds
  encode_time: 100,
  decode_time: 50
}
```

Users can attach handlers:

```elixir
:telemetry.attach(
  "snakebridge-logger",
  [:snakebridge, :call, :stop],
  fn _event, measurements, metadata, _config ->
    Logger.debug("#{metadata.module}.#{metadata.function} took #{measurements.duration}μs")
  end,
  nil
)
```

## Crash Barrier Integration

Snakepit's crash barrier protects against Python crashes:

```elixir
# If idempotent, retry on worker crash
Numpy.random_array([1000], idempotent: true)

# Non-idempotent calls (default) fail immediately on crash
Numpy.array([1, 2, 3])  # idempotent: false
```

When a worker crashes:

1. Snakepit marks the worker as tainted
2. Snakepit spins up a replacement
3. If `idempotent: true`, Snakepit retries on new worker
4. If `idempotent: false`, Snakepit returns `{:error, :worker_crash}`

SnakeBridge passes the `idempotent` flag through to Snakepit.

## Future: Zero-Copy Integration

When zero-copy is implemented, the pattern becomes:

```elixir
# Create shared memory tensor
{:ok, tensor} = Nx.tensor([1, 2, 3], type: :f32)
{:ok, shared} = SnakeBridge.share(tensor)  # Returns ZeroCopyRef

# Pass to Python without copying
{:ok, result} = Numpy.dot(shared, shared)  # shared passed by reference

# Result may also be zero-copy
{:ok, unshared} = SnakeBridge.unshare(result)  # Copy back if needed
```

This requires:

1. Snakepit support for shared memory segments
2. SnakeBridge type encoder for ZeroCopyRef
3. Python-side numpy wrapper using the shared segment

## Summary

| Layer | Responsibility |
|-------|----------------|
| Generated code | Thin wrapper, type specs, docs |
| SnakeBridge.Runtime | Payload building, encoding, delegation |
| SnakeBridge.Types | Lossless Elixir ↔ JSON encoding |
| Snakepit | Pool management, gRPC transport, error handling |
| Python adapter | Tool execution, module import, result encoding |

The key principle: **SnakeBridge is stateless**. All state (sessions, refs,
workers) lives in Snakepit. SnakeBridge just formats requests and decodes
responses.
