# Developer Experience

## The Goal

SnakeBridge v3 should feel **invisible**. Using numpy through SnakeBridge should feel indistinguishable from using a native Elixir library—with all the discoverability, documentation, and IDE support that implies.

## First Contact

### Installation

```elixir
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 3.0",
     libraries: [numpy: "~> 1.26", pandas: "~> 2.0"]}
  ]
end

def project do
  [compilers: [:snakebridge] ++ Mix.compilers(), ...]
end
```

```bash
$ mix deps.get
$ mix compile
SnakeBridge: Scanning project...
SnakeBridge: Generated numpy.ex (3 functions)
Compiled 16 files (0.2s)
```

That's it. No Python setup, no pip commands, no virtual environments. UV handles everything.

### First Use

```elixir
defmodule MyApp.Analysis do
  def run(data) do
    {:ok, arr} = Numpy.array(data)
    {:ok, mean} = Numpy.mean(arr)
    {:ok, std} = Numpy.std(arr)
    {mean, std}
  end
end
```

## IDE Integration

### Autocomplete

When typing in your editor:

```
Numpy.|
       ↓
┌───────────────────────────────────────────────────────┐
│ array         Create an array.                        │
│ mean          Compute the arithmetic mean...          │
│ std           Compute the standard deviation...       │
│ zeros         Return array of zeros...                │
└───────────────────────────────────────────────────────┘
```

Works because generated modules have real function definitions with `@doc`.

### Hover Documentation

```
Numpy.array([1, 2, 3])
      ─────
        │
        ▼
┌───────────────────────────────────────────────────────┐
│ Numpy.array(object)                                   │
│                                                       │
│ Create an array.                                      │
│                                                       │
│ ## Parameters                                         │
│   • object - An array, any object exposing the array │
│     interface, or any (nested) sequence.              │
│                                                       │
│ ## Returns                                            │
│   {:ok, result} | {:error, reason}                    │
└───────────────────────────────────────────────────────┘
```

### Go to Definition

"Go to Definition" on `Numpy.array` takes you to:

```elixir
# lib/snakebridge_generated/numpy.ex
defmodule Numpy do
  @doc """
  Create an array.
  ...
  """
  def array(object) do
    SnakeBridge.Runtime.call(__MODULE__, :array, [object])
  end
end
```

Generated source is human-readable.

## IEx Experience

### Help

```elixir
iex> h Numpy.array

                             Numpy.array/1

Create an array.

## Parameters

  • object - An array, any object exposing the array interface,
    or any (nested) sequence.

## Returns

  {:ok, result} | {:error, reason}
```

### Discovery

```elixir
# What functions are available?
iex> Numpy.__functions__()
[
  {:array, 1, Numpy, "Create an array."},
  {:mean, 1, Numpy, "Compute the arithmetic mean..."},
  {:std, 1, Numpy, "Compute the standard deviation..."}
]

# Search for functions
iex> Numpy.__search__("matrix")
[
  %{name: :matmul, summary: "Matrix product...", relevance: 0.95},
  %{name: :dot, summary: "Dot product...", relevance: 0.87}
]
```

### Interactive Exploration

```elixir
iex> {:ok, arr} = Numpy.array([1, 2, 3, 4, 5])
{:ok, [1, 2, 3, 4, 5]}

iex> Numpy.mean(arr)
{:ok, 3.0}

iex> Numpy.std(arr)
{:ok, 1.4142135623730951}
```

Note: Python object references (`SnakeBridge.PyRef.t()`) are session-bound. For long-lived objects, use `SnakeBridge.Runtime.call_in_session/5` or Snakepit sessions.

## Error Messages

### Function Not Found

```elixir
iex> Numpy.nonexistent([1, 2, 3])

** (UndefinedFunctionError) function Numpy.nonexistent/1 is undefined

    The function 'nonexistent' was not found in numpy.

    Did you mean:
      • Numpy.__search__("nonexistent")
      • Check numpy documentation at https://numpy.org/doc/
```

### Type Errors

```elixir
iex> Numpy.array("invalid input")

{:error, %SnakeBridge.Error{
  type: :python_error,
  python_type: "TypeError",
  message: "Cannot convert 'invalid input' to array",
  suggestion: "Numpy.array expects a list or nested list."
}}
```

## Testing

### Unit Tests (No Python)

Stub the runtime layer so tests remain fast and deterministic:

```elixir
# test/support/runtime_stub.ex
defmodule MyApp.RuntimeStub do
  def call(_module, _function, _args, _opts \\ []), do: {:ok, :stubbed}
end
```

Configure in `config/test.exs`:

```elixir
config :snakebridge, runtime: MyApp.RuntimeStub
```

### Integration Tests (With Python)

Use tags so Python-dependent tests are opt-in:

```elixir
@moduletag :integration
test "numpy mean" do
  {:ok, arr} = Numpy.array([1, 2, 3])
  {:ok, mean} = Numpy.mean(arr)
  assert mean == 2.0
end
```

Run with:

```bash
mix test --include integration
```

### CI Strategy

- Commit `lib/snakebridge_generated/*.ex` and `snakebridge.lock`
- Run `mix compile` with `SNAKEBRIDGE_STRICT=true`
- Skip integration tests unless Python is installed

## Mix Tasks

See [16-mix-tasks.md](16-mix-tasks.md) for full options and examples.

### Generate

```bash
# Generate for detected usage
$ mix snakebridge.generate

# Force regenerate all
$ mix snakebridge.generate --force

# Generate specific library
$ mix snakebridge.generate numpy
```

### Analyze

```bash
$ mix snakebridge.analyze
SnakeBridge Analysis
====================

Generated: 15 symbols
Detected: 12 symbols
Unused: 3 symbols

Libraries:
  numpy (10 symbols)
  pandas (5 symbols)

Status: OK
```

### Prune

```bash
$ mix snakebridge.prune --dry-run
Would prune 3 unused symbols

$ mix snakebridge.prune
Pruned 3 symbols
```

### Verify

```bash
$ mix snakebridge.verify
Verifying...
  ✓ manifest valid
  ✓ lock file matches environment
  ✓ generated source matches manifest
All OK.
```

### Doctor

```bash
$ mix snakebridge.doctor
SnakeBridge Environment Check
=============================

Dependencies:
  ✓ snakepit 0.7.3
  ✓ Python 3.11.5
  ✓ uv 0.1.24

Libraries:
  ✓ numpy ~> 1.26 (1.26.4 installed)
  ✓ pandas ~> 2.0 (2.1.4 installed)

Status: Ready
```

## Debugging

### Verbose Mode

```elixir
# config/dev.exs
config :snakebridge, verbose: true
```

```
[SnakeBridge] Scanning lib/...
[SnakeBridge] Detected: Numpy.array/1, Numpy.mean/1, Numpy.std/1
[SnakeBridge] Checking manifest...
[SnakeBridge] New symbols: Numpy.mean/1, Numpy.std/1
[SnakeBridge] Introspecting numpy...
[SnakeBridge] Generating numpy.ex
[SnakeBridge] Done (145ms)
```

### Scan Debug

```bash
$ mix snakebridge.scan --verbose
Scanning for library calls...

lib/my_app/analysis.ex:
  Line 5: Numpy.array/1
  Line 6: Numpy.mean/1
  Line 7: Numpy.std/1

lib/my_app/ml.ex:
  Line 10: Pandas.DataFrame/1

Total: 4 symbols in 2 files
```

## Testing

### Mocking

```elixir
# test/my_app_test.exs
defmodule MyAppTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  test "analysis returns mean and std" do
    SnakeBridge.RuntimeMock
    |> expect(:call, fn Numpy, :array, [[1,2,3]] -> {:ok, [1,2,3]} end)
    |> expect(:call, fn Numpy, :mean, [[1,2,3]] -> {:ok, 2.0} end)
    |> expect(:call, fn Numpy, :std, [[1,2,3]] -> {:ok, 0.816} end)

    assert {2.0, 0.816} = MyApp.Analysis.run([1, 2, 3])
  end
end
```

### Integration

```elixir
# test/integration/numpy_test.exs
defmodule Integration.NumpyTest do
  use ExUnit.Case
  @moduletag :integration

  test "real numpy call" do
    {:ok, arr} = Numpy.array([1, 2, 3, 4, 5])
    {:ok, mean} = Numpy.mean(arr)
    assert_in_delta mean, 3.0, 0.001
  end
end
```

```bash
$ mix test --include integration
```

## Telemetry

```elixir
:telemetry.attach("snakebridge-logger",
  [:snakebridge, :call, :stop],
  fn _name, measurements, metadata, _config ->
    Logger.debug("#{metadata.module}.#{metadata.function} took #{measurements.duration}ms")
  end,
  nil
)
```

Events:
- `[:snakebridge, :call, :start]` - Python call started
- `[:snakebridge, :call, :stop]` - Python call completed
- `[:snakebridge, :generate, :start]` - Generation started
- `[:snakebridge, :generate, :stop]` - Generation completed
