# Getting Started with SnakeBridge

SnakeBridge lets you call Python from Elixir with type-safe bindings. This guide covers everything you need to start using Python libraries in your Elixir project.

## Prerequisites

Before installing SnakeBridge, ensure you have:

1. **Elixir 1.14+** - Check with `elixir --version`
2. **Python 3.8+** - Check with `python3 --version`
3. **uv** - Fast Python package manager required by Snakepit

### Installing uv

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or via Homebrew
brew install uv
```

## Installation

Add SnakeBridge to your `mix.exs` with the Python libraries you want to use:

```elixir
defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "1.0.0",
      elixir: "~> 1.14",
      deps: deps(),
      python_deps: python_deps(),
      # Required: Add the snakebridge compiler
      compilers: [:snakebridge] ++ Mix.compilers()
    ]
  end

  defp deps do
    [{:snakebridge, "~> 0.10.0"}]
  end

  # Python dependencies - just like Elixir deps
  defp python_deps do
    [
      {:numpy, "1.26.0"},
      {:pandas, "2.0.0", include: ["DataFrame", "read_csv"]}
    ]
  end
end
```

The `compilers: [:snakebridge] ++ Mix.compilers()` line enables automatic Python package installation, type introspection, and wrapper generation at compile time.

Then add runtime configuration in `config/runtime.exs`:

```elixir
import Config
SnakeBridge.ConfigHelper.configure_snakepit!()
```

Finally, fetch dependencies and compile:

```bash
mix deps.get
mix compile
```

## Quick Start Example

### Simple Function Call

Call any Python function with `SnakeBridge.call/4`:

```elixir
# Call math.sqrt(16)
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])
# result = 4.0

# With keyword arguments: round(3.14159, ndigits=2)
{:ok, rounded} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
# rounded = 3.14

# Submodule paths work directly
{:ok, path} = SnakeBridge.call("os.path", "join", ["/home", "user", "file.txt"])
```

### Creating and Using Python Objects (Refs)

When you create a Python object, SnakeBridge returns a "ref" - a handle to the object living in Python memory:

```elixir
# Create a pathlib.Path object
{:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/example.txt"])

# Check if it's a ref
SnakeBridge.ref?(path)  # true

# Call methods on the ref
{:ok, exists?} = SnakeBridge.method(path, "exists", [])

# Access attributes
{:ok, name} = SnakeBridge.attr(path, "name")      # "example.txt"
{:ok, suffix} = SnakeBridge.attr(path, "suffix")  # ".txt"

# Method chaining - parent returns another ref
{:ok, parent} = SnakeBridge.attr(path, "parent")
{:ok, parent_name} = SnakeBridge.attr(parent, "name")  # "tmp"
```

### Getting Module Constants

Access module-level constants with `SnakeBridge.get/3`:

```elixir
{:ok, pi} = SnakeBridge.get("math", "pi")   # 3.141592653589793
{:ok, e} = SnakeBridge.get("math", "e")     # 2.718281828459045
{:ok, sep} = SnakeBridge.get("os", "sep")   # "/" on Unix
```

### Bang Variants

Use bang variants to raise on errors instead of pattern matching:

```elixir
result = SnakeBridge.call!("math", "sqrt", [16])
pi = SnakeBridge.get!("math", "pi")
path = SnakeBridge.call!("pathlib", "Path", ["."])
exists? = SnakeBridge.method!(path, "exists", [])
name = SnakeBridge.attr!(path, "name")
```

## Two Ways to Call Python

SnakeBridge offers two approaches that can coexist in the same project.

### 1. Universal FFI (Runtime, Flexible)

The Universal FFI lets you call any Python module dynamically without code generation:

```elixir
{:ok, result} = SnakeBridge.call("json", "dumps", [%{name: "test"}])
{:ok, hash_obj} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
{:ok, hex} = SnakeBridge.method(hash_obj, "hexdigest", [])
```

**Use Universal FFI when:**
- Calling libraries not in your `python_deps`
- Module paths are determined at runtime
- Writing quick scripts or one-off calls
- Accessing stdlib modules (math, json, os, etc.)

### 2. Generated Wrappers (Compile-time, Typed)

Libraries in `python_deps` get Elixir wrapper modules with type hints and docs:

```elixir
# In mix.exs
defp python_deps do
  [{:numpy, "1.26.0"}, {:pandas, "2.0.0", include: ["DataFrame"]}]
end

# After compilation, use like native Elixir
{:ok, result} = Numpy.mean([1, 2, 3, 4])
{:ok, result} = Numpy.mean([[1, 2], [3, 4]], axis: 0)

# Classes generate new/N constructors
{:ok, df} = Pandas.DataFrame.new(%{"a" => [1, 2], "b" => [3, 4]})
```

**Use Generated Wrappers when:**
- You have core libraries you call frequently
- You want compile-time type hints and ExDoc documentation
- You want IDE autocomplete and signature validation

### Comparison

| Feature | Universal FFI | Generated Wrappers |
|---------|--------------|-------------------|
| Setup | None | Add to `python_deps` |
| Type hints / IDE support | No | Yes |
| Compile-time checks | No | Yes |
| Any module | Yes | Only configured |

**Both can coexist.** A typical project might use generated wrappers for NumPy and Pandas, with Universal FFI for one-off stdlib calls.

## Running Python Code

For scripts and Mix tasks, wrap your code with `run_as_script/2`:

```elixir
SnakeBridge.run_as_script(fn ->
  {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
  IO.inspect(result)
end)
```

This ensures proper startup and shutdown of the Python process pool.

## Next Steps

Explore these guides for more advanced usage:

- **[Universal FFI Guide](UNIVERSAL_FFI.md)** - Complete reference for runtime Python calls
- **[Generated Wrappers Guide](GENERATED_WRAPPERS.md)** - Configuring `python_deps` and wrapper generation
- **[Refs and Sessions Guide](REFS_AND_SESSIONS.md)** - Managing Python object lifecycles
- **[Session Affinity Guide](SESSION_AFFINITY.md)** - Routing stateful calls to the same worker
- **[Type System Guide](TYPE_SYSTEM.md)** - Data encoding between Elixir and Python
- **[Error Handling Guide](ERROR_HANDLING.md)** - Structured error translation
- **[Best Practices Guide](BEST_PRACTICES.md)** - Patterns and recommendations

## See Also

- [API Documentation](https://hexdocs.pm/snakebridge)
- [Examples](https://github.com/nshkrdotcom/snakebridge/tree/main/examples)
- [Snakepit](https://hexdocs.pm/snakepit) - The underlying Python process pool
