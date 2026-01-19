# Generated Wrappers

SnakeBridge generates type-safe Elixir wrappers from Python introspection at compile time.
This provides compile-time guarantees, IDE autocompletion, and documentation integration.

## Overview and Benefits

Generated wrappers offer advantages over the Universal FFI:

- **Type Safety**: Generated `@spec` annotations catch type mismatches at compile time
- **IDE Support**: Autocomplete and inline documentation in your editor
- **Discoverable APIs**: `__functions__/0`, `__classes__/0`, and `__search__/1` for exploration
- **Consistent Arities**: Proper handling of optional args, keyword-only params, and variadics

The trade-off is a compilation step requiring Python at build time (unless using strict mode).

## Configuring python_deps

Python dependencies are declared in your `mix.exs`:

```elixir
def project do
  [
    app: :my_app,
    version: "1.0.0",
    deps: deps(),
    python_deps: python_deps()
  ]
end

defp python_deps do
  [
    {:numpy, "1.26.0"},
    {:pandas, "2.0.0", include: ["DataFrame", "read_csv"]},
    {:dspy, "2.6.5", generate: :all, submodules: true},
    {:math, :stdlib}
  ]
end
```

### Dependency Syntax

```elixir
{:numpy, "1.26.0"}                                    # Version-pinned PyPI package
{:math, :stdlib}                                      # Python standard library
{:pandas, "2.0.0", include: ["DataFrame"]}            # With options
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `include` | list | `[]` | Symbols to always generate |
| `exclude` | list | `[]` | Symbols to never generate |
| `generate` | `:used` or `:all` | `:used` | Generation mode |
| `submodules` | boolean or list | `false` | Include submodules |
| `module_name` | atom | derived | Override Elixir module name |
| `python_name` | string | derived | Override Python module name |
| `streaming` | list | `[]` | Functions that return generators |
| `signature_sources` | list | config default | Ordered list of allowed signature sources |
| `strict_signatures` | boolean | config default | Enforce minimum signature tier for this library |
| `min_signature_tier` | atom | config default | Minimum tier when strict signatures are enabled |
| `stub_search_paths` | list | config default | Additional paths to search for `.pyi` stubs |
| `use_typeshed` | boolean | config default | Enable typeshed lookup for missing stubs |
| `typeshed_path` | string | config default | Typeshed root path |
| `stubgen` | keyword | config default | Stubgen options (enabled, cache_dir) |

### Generation Modes

**`:used` (default)** - Only generates wrappers for symbols detected in your codebase.
The compiler scans `lib/` for calls like `Numpy.mean/1` and generates only those.

**`:all`** - Generates wrappers for all public symbols in the Python module:

```elixir
{:dspy, "2.6.5", generate: :all, submodules: true}
```

### Include and Exclude

```elixir
{:pandas, "2.0.0",
  include: ["DataFrame", "Series", "read_csv"],
  exclude: ["eval", "exec"]}
```

## Compilation Pipeline

The pipeline runs during `mix compile`:

### 1. Configuration

`SnakeBridge.Config.load/0` reads `python_deps` from `mix.exs`.

### 2. Scanning

`SnakeBridge.Scanner` parses Elixir files to detect Python library calls:

```elixir
Numpy.mean(data)           # Function call
Pandas.DataFrame.new(...)  # Class instantiation
```

### 3. Introspection

For detected symbols, Python introspection gathers signatures, types, and docstrings
using Python's `inspect` module.

### 4. Manifest

Results cache in `.snakebridge/manifest.json`:

```json
{
  "version": "0.10.0",
  "symbols": {
    "Numpy.mean/1": {
      "module": "Numpy",
      "function": "mean",
      "parameters": [...],
      "docstring": "Compute the arithmetic mean...",
      "signature_source": "runtime",
      "doc_source": "runtime"
    }
  },
  "classes": {
    "Numpy.Ndarray": { "class": "ndarray", "methods": [...] }
  }
}
```

### 5. Generation

`SnakeBridge.Generator` produces Elixir files in `lib/snakebridge_generated/`.

### 6. Lock Update

`SnakeBridge.Lock` updates `snakebridge.lock` with environment info.

## Max Coverage and Signature Tiers

When `generate: :all` is enabled, SnakeBridge attempts to wrap every public symbol
and records the source tier for signatures and docs in the manifest.

Signature tiers (highest to lowest):
1) `runtime` - `inspect.signature` or `__signature__`
2) `text_signature` - `__text_signature__`
3) `runtime_hints` - runtime type hints
4) `stub` - `.pyi` stubs (local, types- packages, typeshed)
5) `stubgen` - generated stubs fallback
6) `variadic` - fallback wrapper when no signature is available

Doc tiers:
1) `runtime` - runtime docstrings
2) `stub` - stub docstrings
3) `module` - module docstring fallback
4) `empty` - no docstring available

Each symbol records `signature_source`, `signature_detail`, `signature_missing_reason`,
`doc_source`, and `doc_missing_reason` in the manifest.

### Stub Discovery and Configuration

Stub discovery checks, in order:
- Local `.pyi` next to the module or package
- `types-<pkg>` stub packages when installed
- Typeshed when `use_typeshed: true`
- Stubgen fallback when stubs are missing (cached)

Configure stub sources and search paths:

```elixir
config :snakebridge,
  signature_sources: [:runtime, :text_signature, :runtime_hints, :stub, :stubgen, :variadic],
  stub_search_paths: ["priv/python/stubs"],
  use_typeshed: true,
  typeshed_path: "/path/to/typeshed",
  stubgen: [enabled: true, cache_dir: ".snakebridge/stubgen_cache"]
```

### Strict Signature Thresholds

Use `strict_signatures` and `min_signature_tier` (global or per-library) to fail
builds when any symbol falls below the minimum tier.

```elixir
config :snakebridge,
  strict_signatures: true,
  min_signature_tier: :stub

defp python_deps do
  [
    {:pandas, "2.2.0",
     generate: :all,
     strict_signatures: true,
     min_signature_tier: :stub}
  ]
end
```

### Coverage Reports

Enable coverage reports to capture tier counts and issues without warnings:

```elixir
config :snakebridge,
  coverage_report: [output_dir: ".snakebridge/coverage"]
```

Reports are written as `*.coverage.json` and `*.coverage.md`.

## Generated Module Structure

```elixir
defmodule Numpy do
  @moduledoc "SnakeBridge bindings for `numpy`."

  def __snakebridge_python_name__, do: "numpy"
  def __snakebridge_library__, do: "numpy"

  @spec mean(list(), keyword()) :: {:ok, term()} | {:error, Snakepit.Error.t()}
  def mean(a, opts \\ []) do
    SnakeBridge.Runtime.call(__MODULE__, :mean, [a], opts)
  end

  # Discovery
  def __functions__, do: [{:mean, 1, __MODULE__, "Compute the arithmetic mean..."}]
  def __classes__, do: [{Numpy.Ndarray, "ndarray object..."}]
  def __search__(query), do: SnakeBridge.Docs.search(__MODULE__, query)
end
```

### Discovery Functions

- `__functions__/0` - Returns `[{name, arity, module, summary}]`
- `__classes__/0` - Returns `[{module, docstring}]`
- `__search__/1` - Fuzzy search across names and docs

```elixir
iex> Numpy.__functions__() |> Enum.take(3)
[{:mean, 1, Numpy, "Compute the arithmetic mean..."}, ...]
```

## Arity Handling

Python's calling conventions map to Elixir function variants.

### Parameter Classification

| Python Kind | Behavior |
|-------------|----------|
| `POSITIONAL_ONLY` | Counts toward required arity |
| `POSITIONAL_OR_KEYWORD` | Counts toward required arity |
| `VAR_POSITIONAL` (*args) | Variadic list parameter |
| `KEYWORD_ONLY` | Passed via opts keyword list |
| `VAR_KEYWORD` (**kwargs) | Passed via opts keyword list |

### Optional Positional Arguments

```python
def func(a, b=10, c=20): ...
```

Generates multiple arities:

```elixir
def func(a)
def func(a, b)
def func(a, b, c)
def func(a, b, c, opts)
```

### Keyword-Only Arguments

```python
def func(a, *, required_kw, optional_kw=None): ...
```

```elixir
def func(a, opts \\ []) do
  missing = ["required_kw"] -- Keyword.keys(opts)
  if missing != [], do: raise ArgumentError, "Missing required keyword-only arguments..."
  SnakeBridge.Runtime.call(__MODULE__, :func, [a], opts)
end
```

### Variadic Fallback (C Extensions)

Functions without introspectable signatures get multiple arities (up to 8 args):

```elixir
def func()
def func(a)
def func(a, b)
# ... up to 8 args (configurable via :variadic_max_arity)
```

## Class Generation

Python classes become nested Elixir modules:

```elixir
defmodule Numpy.Ndarray do
  @opaque t :: SnakeBridge.Ref.t()

  # Constructor: __init__ -> new
  def new(shape, opts \\ []) do
    SnakeBridge.Runtime.call_class(__MODULE__, :__init__, [shape], opts)
  end

  # Method: ref as first argument
  def reshape(ref, shape, opts \\ []) do
    SnakeBridge.Runtime.call_method(ref, :reshape, [shape], opts)
  end

  # Attribute accessor
  def shape(ref), do: SnakeBridge.Runtime.get_attr(ref, :shape)
end
```

### Method Name Mapping

| Python | Elixir |
|--------|--------|
| `__init__` | `new` |
| `__str__` | `to_string` |
| `__repr__` | `inspect` |
| `__len__` | `length` |
| `__getitem__` | `get` |
| `__setitem__` | `put` |
| `__contains__` | `member?` |

Other dunder methods are skipped.

### Reserved Word Handling

Python names conflicting with Elixir reserved words are prefixed with `py_`:

```elixir
def py_class(ref, opts \\ [])  # Python method named "class"
```

## Strict Mode

Enable strict mode for CI without Python:

```bash
SNAKEBRIDGE_STRICT=1 mix compile
```

Or in config:

```elixir
config :snakebridge, strict: true
```

This strict mode verifies manifest coverage and generated files. For signature tier
enforcement, see the "Strict Signature Thresholds" section above.

### Strict Mode Behavior

1. Load existing manifest (no new introspection)
2. Scan project for Python calls
3. Verify all calls exist in manifest
4. Verify generated files exist
5. Verify all symbols are defined

### Failure Example

```
Strict mode: 3 symbol(s) not in manifest.

Missing:
  - Numpy.new_function/2
  - Pandas.DataFrame.new_method/1

To fix:
  1. Run `mix snakebridge.setup` locally
  2. Run `mix compile` to generate bindings
  3. Commit the updated manifest and generated files
  4. Re-run CI
```

### CI Workflow

```yaml
- name: Build
  env:
    SNAKEBRIDGE_STRICT: 1
  run: mix compile --warnings-as-errors
```

## Lockfile

The `snakebridge.lock` captures environment state:

```json
{
  "version": "0.10.0",
  "environment": {
    "snakebridge_version": "0.10.0",
    "generator_hash": "a1b2c3...",
    "python_version": "3.12.3",
    "elixir_version": "1.18.4",
    "hardware": {
      "accelerator": "cuda",
      "cuda_version": "12.1"
    },
    "platform": { "os": "linux", "arch": "x86_64" }
  },
  "libraries": {
    "numpy": { "requested": "1.26.0", "resolved": "1.26.0" }
  }
}
```

The generator hash triggers regeneration when core logic changes.
Hardware info detects compatibility issues across environments.

### Commit Strategy

Commit both `snakebridge.lock` and `.snakebridge/manifest.json` to ensure:

- Reproducible builds across environments
- Strict mode verification in CI
- Hardware compatibility checking

## See Also

- [Universal FFI](UNIVERSAL_FFI.md) - Runtime Python calls without code generation
- [Refs and Sessions](REFS_AND_SESSIONS.md) - Working with Python object references
- [Type System](TYPE_SYSTEM.md) - Data type mapping between Python and Elixir
- [Best Practices](BEST_PRACTICES.md) - When to use generated wrappers vs Universal FFI
