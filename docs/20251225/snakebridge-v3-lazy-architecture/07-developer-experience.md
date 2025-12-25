# Developer Experience

## The Goal

SnakeBridge v3 should feel **invisible**. A developer using numpy through SnakeBridge should have an experience indistinguishable from using a native Elixir library—with all the discoverability, documentation, and IDE support that implies.

## First Contact Experience

### Installation

```bash
$ mix new my_data_app
$ cd my_data_app
```

```elixir
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 3.0",
     libraries: [
       numpy: "~> 1.26",
       pandas: "~> 2.0"
     ]}
  ]
end
```

```bash
$ mix deps.get
Resolving Hex dependencies...
  snakebridge 3.0.0

$ mix compile
SnakeBridge: Initialized cache at _build/snakebridge
SnakeBridge: Ready (numpy ~> 1.26, pandas ~> 2.0)
```

That's it. No Python setup, no pip commands, no virtual environments to manage. Just add the dependency and go.

### First Use

```elixir
# lib/my_data_app.ex
defmodule MyDataApp do
  def analyze(data) do
    {:ok, arr} = Numpy.array(data)
    {:ok, mean} = Numpy.mean(arr)
    {:ok, std} = Numpy.std(arr)

    %{mean: mean, std: std}
  end
end
```

```bash
$ mix compile
SnakeBridge: Generated Numpy.array/1 (87ms)
SnakeBridge: Generated Numpy.mean/1 (23ms)
SnakeBridge: Generated Numpy.std/1 (21ms)
Compiled 1 file (0.15s)

$ mix compile
Compiled 0 files (0.02s)  # All cached
```

## IDE Integration

### Autocomplete

When typing in your editor:

```elixir
Numpy.|
       ↓
┌─────────────────────────────────────────────────────────────┐
│ abs         Calculate the absolute value element-wise      │
│ add         Add arguments element-wise                      │
│ all         Test whether all array elements along axis...  │
│ allclose    Returns True if two arrays are element-wise... │
│ amax        Return the maximum of an array or maximum...   │
│ amin        Return the minimum of an array or minimum...   │
│ any         Test whether any array element along axis...   │
│ append      Append values to the end of an array           │
│ arange      Return evenly spaced values within interval    │
│ ...                                                         │
└─────────────────────────────────────────────────────────────┘
```

Autocomplete works because:
1. Module stub exists from dependency registration
2. Function list is fetched on-demand (cached after first fetch)
3. Brief summaries come from cached docstrings

### Hover Documentation

Hovering over a function call:

```
Numpy.array([1, 2, 3])
      ─────
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ Numpy.array(object, dtype \\ nil, opts \\ [])               │
│                                                             │
│ Create an array.                                            │
│                                                             │
│ ## Parameters                                               │
│                                                             │
│   • object - An array, any object exposing the array        │
│     interface, or any (nested) sequence.                    │
│   • dtype - The desired data-type for the array             │
│   • opts - Keyword list of optional parameters:             │
│     - copy: Whether to copy the array (default: true)       │
│     - order: Memory layout ('C', 'F', 'K')                  │
│                                                             │
│ ## Returns                                                  │
│                                                             │
│   {:ok, ndarray} | {:error, reason}                         │
│                                                             │
│ ## Example                                                  │
│                                                             │
│   iex> Numpy.array([[1, 2], [3, 4]])                       │
│   {:ok, #Numpy.NDArray<shape: (2, 2), dtype: int64>}       │
└─────────────────────────────────────────────────────────────┘
```

### Go to Definition

"Go to Definition" on `Numpy.array` takes you to:

```elixir
# _build/snakebridge/libraries/numpy/functions/array_1.ex
defmodule Numpy do
  @doc """
  Create an array.
  ...
  """
  @spec array(any()) :: {:ok, reference()} | {:error, term()}
  def array(object) do
    SnakeBridge.Runtime.call("numpy", "array", [object])
  end
end
```

The generated source is human-readable and explains the binding.

### Jump to Python Source

For debugging, you can jump to the actual Python source:

```elixir
iex> Numpy.__source__(:array)
{:ok, "/path/to/venv/lib/python3.11/site-packages/numpy/core/multiarray.py:123"}

# Or open in editor
iex> Numpy.__open__(:array)
# Opens your $EDITOR to the Python source
```

## IEx Experience

### Help

```elixir
iex> h Numpy.array

                             Numpy.array/1

Create an array.

numpy.array(object, dtype=None, *, copy=True, order='K', subok=False,
            ndmin=0, like=None)

## Parameters

  • object - An array, any object exposing the array interface, an object
    whose __array__ method returns an array, or any (nested) sequence.
  • dtype - The desired data-type for the array. If not given, then the
    type will be determined as the minimum type required to hold the
    objects in the sequence.

## Examples

    iex> Numpy.array([1, 2, 3])
    {:ok, #Numpy.NDArray<[1, 2, 3]>}

    iex> Numpy.array([[1, 2], [3, 4]])
    {:ok, #Numpy.NDArray<[[1, 2], [3, 4]]>}

## See Also

  • Numpy.zeros/1 - Create array of zeros
  • Numpy.ones/1 - Create array of ones
  • Numpy.empty/1 - Create uninitialized array
```

### Discovery

```elixir
# What functions are available?
iex> Numpy.functions()
[:abs, :add, :all, :allclose, :amax, :amin, :any, :append, :arange, ...]

# Search for functions
iex> Numpy.search("matrix")
[
  %{name: :matrix, summary: "Returns a matrix from an array-like object..."},
  %{name: :matmul, summary: "Matrix product of two arrays."},
  %{name: :asmatrix, summary: "Interpret the input as a matrix."}
]

# What submodules exist?
iex> Numpy.submodules()
[:linalg, :fft, :random, :polynomial, ...]

# Explore a submodule
iex> Numpy.Linalg.functions()
[:det, :eig, :eigvals, :inv, :lstsq, :matrix_power, :norm, :pinv, ...]
```

### Interactive Exploration

```elixir
# Try things out
iex> {:ok, arr} = Numpy.array([1, 2, 3, 4, 5])
{:ok, #Numpy.NDArray<[1, 2, 3, 4, 5]>}

iex> Numpy.mean(arr)
{:ok, 3.0}

iex> Numpy.std(arr)
{:ok, 1.4142135623730951}

# Chain operations
iex> arr |> Numpy.reshape({5, 1}) |> then(fn {:ok, r} -> Numpy.transpose(r) end)
{:ok, #Numpy.NDArray<shape: (1, 5)>}

# See what's in the cache now
iex> SnakeBridge.Cache.list(Numpy)
[
  {:array, 1, ~U[2025-12-25 10:30:00Z]},
  {:mean, 1, ~U[2025-12-25 10:30:05Z]},
  {:std, 1, ~U[2025-12-25 10:30:08Z]},
  {:reshape, 2, ~U[2025-12-25 10:30:12Z]},
  {:transpose, 1, ~U[2025-12-25 10:30:15Z]}
]
```

## Error Messages

### Function Not Found

```elixir
iex> Numpy.nonexistent_function([1, 2, 3])

** (UndefinedFunctionError) function Numpy.nonexistent_function/1 is undefined

    SnakeBridge could not find 'nonexistent_function' in numpy 1.26.4.

    Did you mean one of these?
      • Numpy.function (no such function, but...)
      • Search with: Numpy.search("nonexistent")

    Or check numpy documentation:
      https://numpy.org/doc/stable/reference/
```

### Type Errors

```elixir
iex> Numpy.array("not a valid input for array creation context")

{:error, %SnakeBridge.PythonError{
  type: "TypeError",
  message: "Invalid input type for numpy.array",
  python_traceback: """
    File "numpy/core/multiarray.py", line 123
    ...
  """,
  suggestion: "Numpy.array expects a list or nested list. Got: binary"
}}
```

### Version Compatibility

```elixir
# If you try to use a function that doesn't exist in your numpy version
iex> Numpy.new_function_in_2_0([1, 2, 3])

** (CompileError) Numpy.new_function_in_2_0/1 is not available in numpy 1.26.4

    This function was added in numpy 2.0.0.

    Options:
      1. Update numpy version in mix.exs to "~> 2.0"
      2. Use an alternative function (see suggestions below)

    Suggested alternatives:
      • Numpy.old_equivalent_function/1
```

## Debugging

### Verbose Mode

```elixir
# config/dev.exs
config :snakebridge, verbose: true
```

```
[SnakeBridge] Starting compilation for MyApp
[SnakeBridge] Detected: Numpy.array/1 (not in cache)
[SnakeBridge] Introspecting numpy.array...
[SnakeBridge]   Parameters: [object, dtype, copy, order, subok, ndmin, like]
[SnakeBridge]   Docstring: 458 chars
[SnakeBridge] Generating Numpy.array/1...
[SnakeBridge] Generated in 87ms, cached at libraries/numpy/functions/array_1.beam
[SnakeBridge] Detected: Numpy.mean/1 (not in cache)
[SnakeBridge] Batch introspection: [mean, std] (same UV session)
[SnakeBridge] Generated Numpy.mean/1 in 23ms
[SnakeBridge] Generated Numpy.std/1 in 21ms
[SnakeBridge] Compilation complete: 3 generated, 0 cached
```

### Cache Inspection

```elixir
iex> SnakeBridge.Cache.stats()
%{
  total_entries: 156,
  total_size_mb: 2.3,
  by_library: %{
    "numpy" => %{entries: 85, size_mb: 1.2},
    "pandas" => %{entries: 45, size_mb: 0.8}
  },
  cache_hits_session: 234,
  cache_misses_session: 3
}

iex> SnakeBridge.Cache.entry(:Numpy, :array, 1)
%{
  generated_at: ~U[2025-12-25 10:30:00Z],
  last_used: ~U[2025-12-25 14:45:00Z],
  use_count: 47,
  library_version: "1.26.4",
  source_file: "_build/snakebridge/libraries/numpy/functions/array_1.ex",
  beam_file: "_build/snakebridge/libraries/numpy/functions/array_1.beam"
}
```

### Python Process Inspection

```elixir
iex> SnakeBridge.Runtime.status()
%{
  python_version: "3.11.5",
  uv_version: "0.1.24",
  active_calls: 0,
  total_calls_session: 127,
  average_call_time_ms: 2.3,
  libraries_loaded: [:numpy, :pandas]
}
```

## Mix Tasks

### Analyze

```bash
$ mix snakebridge.analyze

SnakeBridge Cache Analysis
==========================

Total entries: 156
Cache size: 2.3 MB
Libraries: 3

By Library:
  numpy (85 entries, 1.2 MB)
    Most used: array/1 (523 calls), zeros/2 (234 calls)
    Unused 30+ days: 12 entries

  pandas (45 entries, 0.8 MB)
    Most used: DataFrame/1 (189 calls), read_csv/1 (145 calls)
    Unused 30+ days: 5 entries

  sympy (26 entries, 0.3 MB)
    Most used: Symbol/1 (89 calls), solve/2 (67 calls)
    Unused 30+ days: 8 entries

Recommendations:
  - 25 entries unused for 30+ days (run: mix snakebridge.prune --dry-run)
  - sympy hasn't been used in 5 days
```

### List

```bash
$ mix snakebridge.list

Configured Libraries:
  numpy (~> 1.26) as Numpy
    Installed: 1.26.4
    Cached functions: 85
    Last used: Today

  pandas (~> 2.0) as Pandas
    Installed: 2.1.4
    Cached functions: 45
    Last used: Today

  sympy (~> 1.12) as Sympy
    Installed: 1.12.0
    Cached functions: 26
    Last used: 5 days ago
```

### Generate (Pre-warming)

```bash
# Generate specific functions ahead of time
$ mix snakebridge.generate Numpy.fft Numpy.ifft Numpy.fft2
Generated 3 functions in 245ms

# Generate from a file listing function calls
$ mix snakebridge.generate --from lib/
Scanning lib/ for SnakeBridge function calls...
Found 45 unique function calls
Already cached: 42
Generating: 3
Done in 312ms
```

### Export/Import

```bash
# Export cache for CI or team sharing
$ mix snakebridge.cache.export --output cache.tar.gz
Exported 156 entries (2.3 MB compressed)

# Import on another machine
$ mix snakebridge.cache.import cache.tar.gz
Imported 156 entries
Verified checksums: OK
```

## Editor Plugins

### VS Code

```json
// .vscode/settings.json
{
  "elixir.snakebridge.enabled": true,
  "elixir.snakebridge.showPythonDocs": true,
  "elixir.snakebridge.cacheIndicator": true
}
```

Features:
- Autocomplete with Python docstrings
- Hover documentation
- "Generate binding" code action
- Cache status in status bar
- "View Python source" command

### Vim/Neovim

```lua
-- lua/snakebridge.lua
require('snakebridge').setup({
  show_python_docs = true,
  keymaps = {
    generate = '<leader>sg',
    view_python = '<leader>sp',
    search = '<leader>ss'
  }
})
```

### Emacs

```elisp
;; init.el
(use-package snakebridge
  :hook (elixir-mode . snakebridge-mode)
  :config
  (setq snakebridge-show-python-docs t))
```

## Testing

### Mocking Python Calls

```elixir
# test/support/snakebridge_mock.ex
defmodule SnakeBridge.Mock do
  def mock(Numpy, :array, fn [data] ->
    {:ok, %{type: :mock_array, data: data}}
  end)

  def mock(Numpy, :mean, fn [_arr] ->
    {:ok, 42.0}
  end)
end
```

```elixir
# test/my_app_test.exs
defmodule MyAppTest do
  use ExUnit.Case
  import SnakeBridge.Mock

  setup do
    mock(Numpy, :array, fn [data] -> {:ok, data} end)
    mock(Numpy, :mean, fn [_] -> {:ok, 5.0} end)
    :ok
  end

  test "analyze returns mean and std" do
    result = MyApp.analyze([1, 2, 3])
    assert result.mean == 5.0
  end
end
```

### Integration Tests

```elixir
# test/integration/numpy_test.exs
defmodule NumpyIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  test "array creation and operations" do
    {:ok, arr} = Numpy.array([1, 2, 3, 4, 5])
    {:ok, mean} = Numpy.mean(arr)

    assert_in_delta mean, 3.0, 0.001
  end
end
```

```bash
# Run integration tests (requires Python)
$ mix test --include integration
```

## Performance Monitoring

### Telemetry Events

```elixir
:telemetry.attach("snakebridge-logger",
  [:snakebridge, :call, :stop],
  fn _name, measurements, metadata, _config ->
    Logger.debug("#{metadata.module}.#{metadata.function} took #{measurements.duration}ms")
  end,
  nil
)
```

Events emitted:
- `[:snakebridge, :call, :start]` - Python call started
- `[:snakebridge, :call, :stop]` - Python call completed
- `[:snakebridge, :generate, :start]` - Binding generation started
- `[:snakebridge, :generate, :stop]` - Binding generation completed
- `[:snakebridge, :cache, :hit]` - Cache hit
- `[:snakebridge, :cache, :miss]` - Cache miss

### Dashboard Integration

```elixir
# lib/my_app_web/telemetry.ex
defmodule MyAppWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def metrics do
    [
      summary("snakebridge.call.duration",
        tags: [:module, :function],
        unit: {:native, :millisecond}
      ),
      counter("snakebridge.cache.hit"),
      counter("snakebridge.cache.miss"),
      last_value("snakebridge.cache.size")
    ]
  end
end
```
