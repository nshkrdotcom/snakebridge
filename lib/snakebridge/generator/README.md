# SnakeBridge Generator

The SnakeBridge Generator is a complete code generation system that introspects Python libraries and generates type-safe Elixir adapter modules with full documentation and typespecs.

## Architecture

The generator consists of five main modules:

```
┌─────────────────┐
│   Introspector  │  Shells out to Python to introspect modules
└────────┬────────┘
         │ JSON introspection data
         ▼
┌─────────────────┐
│   TypeMapper    │  Maps Python types to Elixir typespec AST
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  DocFormatter   │  Formats Python docstrings as Elixir docs
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  SourceWriter   │  Generates complete Elixir module source
└─────────────────┘
```

## Modules

### 1. Introspector

**Module:** `SnakeBridge.Generator.Introspector`

Shells out to a Python script (`priv/python/introspect.py`) to analyze Python modules and extract their API information.

**Usage:**

```elixir
{:ok, introspection} = Introspector.introspect("json")
# => %{
#   "module" => "json",
#   "functions" => [
#     %{
#       "name" => "dumps",
#       "parameters" => [...],
#       "return_type" => %{"type" => "str"},
#       "docstring" => %{"summary" => "..."}
#     }
#   ],
#   "classes" => [...]
# }
```

**Features:**

- Uses `:code.priv_dir(:snakebridge)` to locate the Python script
- Finds Python executable automatically (`python3` or `python`)
- Parses JSON output from the introspection script
- Returns structured data about functions, classes, types, and documentation

### 2. TypeMapper

**Module:** `SnakeBridge.Generator.TypeMapper`

Converts Python type annotations to Elixir typespec AST using `quote`.

**Usage:**

```elixir
python_type = %{"type" => "list", "element_type" => %{"type" => "str"}}
spec_ast = TypeMapper.to_spec(python_type)
Macro.to_string(spec_ast)
# => "list(String.t())"
```

**Type Mappings:**

| Python Type | Elixir Type |
|------------|-------------|
| `int` | `integer()` |
| `float` | `float()` |
| `str` | `String.t()` |
| `bool` | `boolean()` |
| `bytes` | `binary()` |
| `None` | `nil` |
| `list[T]` | `list(T)` |
| `dict[K, V]` | `map(K, V)` |
| `tuple[T1, T2]` | `{T1, T2}` |
| `set[T]` | `MapSet.t(T)` |
| `Optional[T]` | `T \| nil` |
| `Union[T1, T2]` | `T1 \| T2` |
| `ClassName` | `ClassName.t()` |
| `Any` | `any()` |

### 3. DocFormatter

**Module:** `SnakeBridge.Generator.DocFormatter`

Formats Python docstrings into Elixir documentation with proper Markdown formatting.

**Usage:**

```elixir
# Module documentation
moduledoc = DocFormatter.module_doc(introspection)
# => "JSON encoder and decoder.\n\nProvides functions..."

# Function documentation
doc = DocFormatter.function_doc(func_info)
# => "Serialize obj to a JSON string.\n\n## Parameters\n\n  * `obj` - ..."
```

**Features:**

- Extracts summary and description from Python docstrings
- Generates `## Parameters` section with descriptions
- Generates `## Returns` section
- Generates `## Raises` section for exceptions
- Preserves module metadata (version, source file)

### 4. SourceWriter

**Module:** `SnakeBridge.Generator.SourceWriter`

Generates complete, formatted Elixir source code from introspection data.

**Usage:**

```elixir
source = SourceWriter.generate(introspection,
  module_name: "MyPythonLib",
  use_snakebridge: true,
  add_python_annotations: true
)
# => "defmodule MyPythonLib do\n  @moduledoc \"...\"\n  ..."

# Write to file
:ok = SourceWriter.generate_file(introspection, "lib/my_python_lib.ex")
```

**Options:**

- `:module_name` - The Elixir module name (defaults to CamelCase of Python module)
- `:use_snakebridge` - Whether to add `use SnakeBridge.Adapter` (default: true)
- `:add_python_annotations` - Whether to add `@python_function` annotations (default: true)

**Features:**

- Generates complete module AST with `defmodule`
- Adds `@moduledoc` from Python docstrings
- Generates `@spec` declarations from Python type annotations
- Creates `@doc` strings for each function
- Handles Python classes as nested Elixir modules
- Formats output using `Code.format_string!/2`

## Complete Workflow Example

```elixir
alias SnakeBridge.Generator.{Introspector, SourceWriter}

# Step 1: Introspect Python module
{:ok, introspection} = Introspector.introspect("math")

# Step 2: Generate Elixir source code
source = SourceWriter.generate(introspection,
  module_name: "PythonMath",
  use_snakebridge: true
)

# Step 3: Write to file (optional)
:ok = SourceWriter.generate_file(
  introspection,
  "lib/python_math.ex",
  module_name: "PythonMath"
)
```

## Generated Code Example

Given a Python module with:

```python
def add(a: int, b: int) -> int:
    """Add two numbers.

    Args:
        a: First number
        b: Second number

    Returns:
        Sum of a and b
    """
    return a + b
```

The generator produces:

```elixir
defmodule MyLib do
  @moduledoc "Python module: mylib"

  use SnakeBridge.Adapter

  @doc \"\"\"
  Add two numbers.

  ## Parameters

    * `a` (integer) - First number
    * `b` (integer) - Second number

  ## Returns

  Sum of a and b
  \"\"\"
  @spec add(integer(), integer()) :: integer()
  @python_function "add"
  def add(a, b) do
    __python_call__("add", [a, b])
  end
end
```

## Testing

The generator includes comprehensive tests:

- **`type_mapper_test.exs`** - Tests for all type mappings
- **`integration_test.exs`** - End-to-end workflow tests

Run tests:

```bash
mix test test/snakebridge/generator/
```

## Python Introspection Script

The Python introspection script (`priv/python/introspect.py`) uses Python's `inspect` module to extract:

- Function signatures and type hints
- Parameter types and default values
- Return type annotations
- Docstrings (with optional enhanced parsing)
- Class definitions and methods
- Module metadata

The script outputs JSON to stdout, which is parsed by the Introspector module.

## Limitations and Future Work

Current limitations:

- Generic types like `Callable` are mapped to `any()`
- Complex Python class hierarchies are simplified
- Default values are represented as strings
- No support for overloaded functions (Python doesn't have true overloading)

Future enhancements:

- Support for Python decorators
- Better handling of class inheritance
- Generation of property accessors
- Support for async functions
- Integration with Python stub files (`.pyi`)
