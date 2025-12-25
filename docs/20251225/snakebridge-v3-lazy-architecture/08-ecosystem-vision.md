# Ecosystem Vision

## The Long-Term Goal

SnakeBridge v3 is a foundation for something larger: **hex_snake**, a community-powered ecosystem that makes Python libraries first-class citizens in the Elixir world.

```
Today:           Individual projects configure their own Python bindings
Tomorrow:        Community-curated, type-safe, documented Python packages on Hex

               ┌─────────────────────────────────────────────────────────────┐
               │                         hex_snake                           │
               │                                                             │
               │   Curated Python library bindings published to Hex          │
               │   with Elixir-native documentation, typespecs, and tests    │
               │                                                             │
               └─────────────────────────────────────────────────────────────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ▼                     ▼                     ▼
            ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
            │ hex_numpy   │       │ hex_pandas  │       │ hex_torch   │
            │ ~> 1.26.0   │       │ ~> 2.1.0    │       │ ~> 2.1.0    │
            │             │       │             │       │             │
            │ Full types  │       │ Full types  │       │ Full types  │
            │ ExDoc       │       │ ExDoc       │       │ ExDoc       │
            │ Tests       │       │ Tests       │       │ Tests       │
            └─────────────┘       └─────────────┘       └─────────────┘
```

## Evolution Stages

### Stage 1: SnakeBridge v3 (Current)

**Individual project bindings**

```elixir
# Each project configures its own libraries
{:snakebridge, "~> 3.0",
 libraries: [
   numpy: "~> 1.26",
   pandas: "~> 2.0"
 ]}
```

Features:
- Lazy compilation
- Local caching
- On-demand documentation
- Per-project configuration

### Stage 2: Shared Cache Infrastructure

**Team and community cache sharing**

```elixir
# config/config.exs
config :snakebridge,
  shared_cache: "https://cache.snakebridge.io",
  auth: {:env, "SNAKEBRIDGE_TOKEN"}
```

```
Developer A                    Cache Server                  Developer B
    │                              │                              │
    │  Generate Numpy.array/1      │                              │
    │ ─────────────────────────────►                              │
    │                              │                              │
    │                        Store │                              │
    │                              │                              │
    │                              │◄───────────────────────────  │
    │                              │   Request Numpy.array/1      │
    │                              │                              │
    │                              │  ─────────────────────────►  │
    │                              │   Return cached binding      │
    │                              │                              │
```

Features:
- Central cache server
- Instant bindings for common functions
- Reduced compile times for new projects
- Organization-private caches

### Stage 3: Community Binding Packages

**hex_snake: Curated packages on Hex**

```elixir
# mix.exs
defp deps do
  [
    # Core runtime
    {:snakebridge, "~> 3.0"},

    # Community-maintained packages
    {:hex_numpy, "~> 1.26.0"},
    {:hex_pandas, "~> 2.1.0"},
    {:hex_sklearn, "~> 1.3.0"}
  ]
end
```

Each `hex_*` package provides:
- **Pre-generated bindings** — No compile-time generation needed
- **Complete typespecs** — Full `@spec` annotations
- **ExDoc documentation** — Native Elixir docs with examples
- **Test coverage** — Verified against real Python library
- **Version tracking** — Matches Python library versions

```elixir
# hex_numpy provides:
defmodule Numpy do
  @moduledoc """
  Elixir bindings for NumPy, the fundamental package for scientific computing.

  ## Installation

      {:hex_numpy, "~> 1.26.0"}

  ## Quick Start

      iex> {:ok, arr} = Numpy.array([1, 2, 3, 4, 5])
      iex> Numpy.mean(arr)
      {:ok, 3.0}

  ## Modules

  - `Numpy` - Core array operations
  - `Numpy.Linalg` - Linear algebra
  - `Numpy.FFT` - Fourier transforms
  - `Numpy.Random` - Random number generation

  For complete documentation, see https://hexdocs.pm/hex_numpy
  """

  @doc """
  Create an array from a list or nested list.

  ## Examples

      iex> Numpy.array([1, 2, 3])
      {:ok, #Numpy.NDArray<[1, 2, 3]>}

      iex> Numpy.array([[1, 2], [3, 4]])
      {:ok, #Numpy.NDArray<[[1, 2], [3, 4]]>}

  ## Parameters

  - `data` - List or nested list of numbers
  - `opts` - Optional keyword list:
    - `:dtype` - Data type (`:float64`, `:int32`, etc.)
    - `:order` - Memory layout (`:c`, `:fortran`)

  ## Returns

  - `{:ok, array}` - Success with NDArray reference
  - `{:error, reason}` - Failure with error details
  """
  @spec array(list(), keyword()) :: {:ok, Numpy.NDArray.t()} | {:error, term()}
  def array(data, opts \\ []) do
    # Pre-compiled binding
  end
end
```

### Stage 4: Intelligent Package Selection

**Smart dependency resolution**

```elixir
# mix.exs - Just declare what you need
{:snakebridge, "~> 3.0",
 libraries: [:numpy, :pandas, :sklearn]}
```

SnakeBridge automatically:
1. Checks if `hex_numpy`, `hex_pandas`, `hex_sklearn` exist
2. Uses community packages when available
3. Falls back to lazy generation for unpackaged libraries
4. Warns about version mismatches

```
$ mix deps.get
Resolving dependencies...
  snakebridge 3.0.0
  hex_numpy 1.26.0 (community package)
  hex_pandas 2.1.0 (community package)

Note: sklearn will use lazy generation (no hex_sklearn package yet)
      Consider contributing: https://github.com/hex-snake/hex_sklearn
```

## Community Packages

### Package Structure

```
hex_numpy/
├── lib/
│   ├── numpy.ex                 # Main module
│   ├── numpy/
│   │   ├── array.ex            # NDArray type
│   │   ├── linalg.ex           # Linear algebra
│   │   ├── fft.ex              # Fourier transforms
│   │   ├── random.ex           # Random number generation
│   │   └── ...
│   └── numpy_runtime.ex        # Runtime bridge to Python
├── test/
│   ├── numpy_test.exs
│   ├── numpy/
│   │   ├── array_test.exs
│   │   ├── linalg_test.exs
│   │   └── ...
│   └── integration/
│       └── python_test.exs
├── pages/
│   ├── getting_started.md
│   ├── type_mappings.md
│   ├── performance.md
│   └── ...
├── mix.exs
└── README.md
```

### Package Generation

Community packages are generated using SnakeBridge tooling:

```bash
# Generate a new hex_* package
$ mix snakebridge.hex.generate numpy --output hex_numpy
Creating hex_numpy package...
  Introspecting numpy...
  Found 892 functions, 45 classes
  Generating bindings...
  Generating tests...
  Generating documentation...

Package created at hex_numpy/

Next steps:
  1. Review generated code
  2. Add Elixir-specific examples
  3. Run tests: cd hex_numpy && mix test
  4. Publish: mix hex.publish
```

### Package Maintenance

```yaml
# .github/workflows/sync.yml
name: Sync with Python library

on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly

jobs:
  check-upstream:
    steps:
      - name: Check for new numpy version
        run: |
          LATEST=$(pip index versions numpy | head -1)
          CURRENT=$(grep numpy_version mix.exs)
          if [ "$LATEST" != "$CURRENT" ]; then
            # Create PR with updated bindings
          fi
```

## Type Safety

### Elixir Types for Python Objects

```elixir
defmodule Numpy.NDArray do
  @type t :: %__MODULE__{
    ref: reference(),
    shape: tuple(),
    dtype: dtype(),
    device: :cpu | :cuda
  }

  @type dtype ::
    :float16 | :float32 | :float64 |
    :int8 | :int16 | :int32 | :int64 |
    :uint8 | :uint16 | :uint32 | :uint64 |
    :bool | :complex64 | :complex128

  defstruct [:ref, :shape, :dtype, :device]
end
```

### Typed Function Signatures

```elixir
defmodule Numpy do
  @spec array(list() | Numpy.NDArray.t()) :: {:ok, Numpy.NDArray.t()} | {:error, term()}
  @spec zeros(tuple()) :: {:ok, Numpy.NDArray.t()} | {:error, term()}
  @spec dot(Numpy.NDArray.t(), Numpy.NDArray.t()) :: {:ok, Numpy.NDArray.t()} | {:error, term()}
  @spec reshape(Numpy.NDArray.t(), tuple()) :: {:ok, Numpy.NDArray.t()} | {:error, term()}
end
```

### Dialyzer Integration

```elixir
# Dialyzer catches type errors
arr = Numpy.array([1, 2, 3])
Numpy.dot(arr, "not an array")  # Dialyzer warning: expected NDArray.t()
```

## Cross-Library Integration

### Numpy + Pandas

```elixir
# Seamless interop between libraries
{:ok, df} = Pandas.read_csv("data.csv")
{:ok, arr} = Pandas.to_numpy(df)  # Convert to Numpy array
{:ok, result} = Numpy.mean(arr, axis: 0)
```

### Shared Object Protocol

```elixir
defprotocol SnakeBridge.ArrayLike do
  @doc "Convert to numpy-compatible array"
  def to_numpy(data)
end

defimpl SnakeBridge.ArrayLike, for: List do
  def to_numpy(list), do: Numpy.array(list)
end

defimpl SnakeBridge.ArrayLike, for: Pandas.DataFrame do
  def to_numpy(df), do: Pandas.to_numpy(df)
end

defimpl SnakeBridge.ArrayLike, for: Numpy.NDArray do
  def to_numpy(arr), do: {:ok, arr}
end
```

## Performance Optimizations

### Zero-Copy Data Transfer (Future)

```elixir
# Large arrays transferred via shared memory
{:ok, arr} = Numpy.zeros({10_000, 10_000})
# Array data lives in shared memory
# Elixir and Python both access same memory

{:ok, result} = Numpy.dot(arr, arr)
# No copying between processes
```

### GPU Support

```elixir
# CUDA integration
{:ok, gpu_arr} = Numpy.array([1, 2, 3], device: :cuda)
{:ok, result} = Numpy.matmul(gpu_arr, gpu_arr)
# Computation happens on GPU
```

### Batch Operations

```elixir
# Batch multiple operations into single Python call
results = SnakeBridge.batch do
  a = Numpy.array([1, 2, 3])
  b = Numpy.array([4, 5, 6])
  c = Numpy.add(a, b)
  d = Numpy.multiply(c, 2)
  Numpy.sum(d)
end
# All operations executed in one round-trip
```

## Distribution

### Hex.pm Integration

```
https://hex.pm/packages?search=hex_

Results:
  hex_numpy          1.26.0    NumPy bindings for Elixir
  hex_pandas         2.1.0     Pandas bindings for Elixir
  hex_scipy          1.11.0    SciPy bindings for Elixir
  hex_matplotlib     3.8.0     Matplotlib bindings for Elixir
  hex_sklearn        1.3.0     Scikit-learn bindings for Elixir
  hex_torch          2.1.0     PyTorch bindings for Elixir
  hex_tensorflow     2.15.0    TensorFlow bindings for Elixir
  hex_transformers   4.35.0    Hugging Face Transformers for Elixir
  ...
```

### HexDocs Integration

```
https://hexdocs.pm/hex_numpy

NumPy for Elixir
================

Complete Elixir bindings for NumPy, the fundamental package for
scientific computing with Python.

Installation
------------
Add to your mix.exs:

    {:hex_numpy, "~> 1.26.0"}

Quick Start
-----------
    iex> {:ok, arr} = Numpy.array([[1, 2], [3, 4]])
    iex> {:ok, inv} = Numpy.Linalg.inv(arr)

Modules
-------
- Numpy - Core array operations
- Numpy.Linalg - Linear algebra
- Numpy.FFT - Discrete Fourier Transform
- Numpy.Random - Random sampling
```

## Governance

### hex_snake Organization

```
github.com/hex-snake/
├── snakebridge          # Core runtime
├── hex_numpy            # NumPy bindings
├── hex_pandas           # Pandas bindings
├── hex_scipy            # SciPy bindings
├── ...
├── generator            # Package generation tools
├── docs                 # Ecosystem documentation
└── community            # Contribution guidelines
```

### Contribution Model

1. **Core maintainers** — Maintain snakebridge runtime
2. **Package maintainers** — Own individual hex_* packages
3. **Contributors** — Submit PRs for improvements
4. **Sponsors** — Fund development and hosting

### Quality Standards

All hex_* packages must:
- [ ] Pass automated test suite
- [ ] Include complete typespecs
- [ ] Provide ExDoc documentation
- [ ] Match Python library version
- [ ] Follow Elixir style guide
- [ ] Support latest 2 Elixir versions

## Timeline

### 2025 Q1-Q2: SnakeBridge v3

- [x] Design v3 architecture
- [ ] Implement lazy compilation
- [ ] Implement accumulator cache
- [ ] Implement documentation system
- [ ] Implement pruning system
- [ ] Release v3.0.0

### 2025 Q3: Shared Cache

- [ ] Design cache server protocol
- [ ] Implement cache server
- [ ] Deploy public cache
- [ ] Organization support

### 2025 Q4: First Community Packages

- [ ] hex_numpy (flagship)
- [ ] hex_pandas
- [ ] hex_scipy
- [ ] Package generator tool

### 2026: Ecosystem Expansion

- [ ] 20+ community packages
- [ ] Type safety improvements
- [ ] Performance optimizations
- [ ] IDE plugin ecosystem

## Call to Action

SnakeBridge v3 is the foundation. The ecosystem vision requires community involvement:

1. **Use SnakeBridge v3** — The lazy compilation model builds the data we need
2. **Contribute bindings** — Help create hex_* packages for your favorite libraries
3. **Report issues** — Help us understand real-world usage patterns
4. **Sponsor development** — Support ongoing maintenance and infrastructure

Together, we can make Python's incredible ecosystem a natural part of Elixir development.
