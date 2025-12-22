# Type Mapping System

## Overview

AutoBridge must translate between Python's dynamic type system and Elixir's statically-typed world. This document defines the mapping strategies and type inference approaches.

---

## Core Type Mappings

### Primitive Types

| Python Type | Elixir Type | Notes |
|-------------|-------------|-------|
| `str` | `String.t()` | UTF-8 compatible |
| `int` | `integer()` | Arbitrary precision |
| `float` | `float()` | IEEE 754 |
| `bool` | `boolean()` | `True` → `true` |
| `None` | `nil` | |
| `bytes` | `binary()` | Raw bytes |

### Collection Types

| Python Type | Elixir Type | Notes |
|-------------|-------------|-------|
| `list` | `list(term())` | Heterogeneous |
| `list[T]` | `[t()]` | Homogeneous, inferred |
| `tuple` | `tuple()` | Fixed structure |
| `dict` | `map()` | Key-value |
| `dict[str, T]` | `%{String.t() => t()}` | Typed dict |
| `set` | `MapSet.t()` | Unordered unique |

### Special Types

| Python Type | Elixir Type | Notes |
|-------------|-------------|-------|
| `Optional[T]` | `t() \| nil` | Nullable |
| `Union[A, B]` | `a() \| b()` | Union types |
| `Any` | `term()` | Escape hatch |
| `Callable` | `function()` | For callbacks |

---

## Library-Specific Type Mappings

### SymPy Types

```elixir
@type expression :: String.t() | map()
@type symbol :: atom()
@type equation :: {:eq, expression(), expression()}
@type solution :: [expression()]
@type substitution :: %{symbol() => expression()}

# Complex SymPy objects serialized as strings
@type sympy_expr :: String.t()
```

**Serialization Strategy**:
```elixir
# SymPy expressions → string (default)
SymPy.sympify("x**2 + 1")
# Returns: {:ok, "x**2 + 1"}

# SymPy expressions → structured map (optional)
SymPy.sympify("x**2 + 1", format: :structured)
# Returns: {:ok, %{type: :add, args: [%{type: :pow, ...}, 1]}}
```

### pylatexenc Types

```elixir
@type latex_string :: String.t()
@type unicode_string :: String.t()
@type latex_node :: %{
  type: :text | :macro | :group | :environment,
  content: term(),
  position: {integer(), integer()}
}
```

### Math-Verify Types

```elixir
@type parse_result :: {:ok, expression()} | {:error, parse_error()}
@type verify_result :: {:ok, boolean()} | {:error, verify_error()}
@type extraction_config :: :latex | :expr | :string | keyword()

@type parse_error :: 
  :invalid_syntax | 
  :unsupported_expression | 
  {:extraction_failed, String.t()}
```

---

## Type Inference Algorithm

### From Observations

```elixir
defmodule AutoBridge.TypeInference do
  @doc """
  Infer Elixir type from observed Python values.
  """
  def infer_type(observations) do
    observations
    |> Enum.map(&classify_value/1)
    |> find_common_type()
    |> to_typespec()
  end
  
  defp classify_value(value) when is_binary(value), do: :string
  defp classify_value(value) when is_integer(value), do: :integer
  defp classify_value(value) when is_float(value), do: :float
  defp classify_value(value) when is_boolean(value), do: :boolean
  defp classify_value(value) when is_nil(value), do: :nil
  defp classify_value(value) when is_list(value) do
    case value do
      [] -> {:list, :any}
      [h | _] -> {:list, classify_value(h)}
    end
  end
  defp classify_value(value) when is_map(value), do: :map
  defp classify_value(_), do: :any
  
  defp find_common_type(types) do
    unique = Enum.uniq(types)
    case unique do
      [single] -> single
      multiple -> {:union, multiple}
    end
  end
  
  defp to_typespec(:string), do: "String.t()"
  defp to_typespec(:integer), do: "integer()"
  defp to_typespec(:float), do: "float()"
  defp to_typespec(:boolean), do: "boolean()"
  defp to_typespec(:nil), do: "nil"
  defp to_typespec({:list, inner}), do: "[#{to_typespec(inner)}]"
  defp to_typespec(:map), do: "map()"
  defp to_typespec(:any), do: "term()"
  defp to_typespec({:union, types}) do
    types |> Enum.map(&to_typespec/1) |> Enum.join(" | ")
  end
end
```

### From Python Type Hints

```elixir
defmodule AutoBridge.TypeHints do
  @doc """
  Parse Python type hints to Elixir typespecs.
  """
  def parse_hint("str"), do: "String.t()"
  def parse_hint("int"), do: "integer()"
  def parse_hint("float"), do: "float()"
  def parse_hint("bool"), do: "boolean()"
  def parse_hint("None"), do: "nil"
  def parse_hint("Any"), do: "term()"
  
  def parse_hint("list[" <> rest) do
    inner = String.trim_trailing(rest, "]")
    "[#{parse_hint(inner)}]"
  end
  
  def parse_hint("dict[str, " <> rest) do
    value_type = String.trim_trailing(rest, "]")
    "%{String.t() => #{parse_hint(value_type)}}"
  end
  
  def parse_hint("Optional[" <> rest) do
    inner = String.trim_trailing(rest, "]")
    "#{parse_hint(inner)} | nil"
  end
  
  def parse_hint("Union[" <> rest) do
    types = rest
    |> String.trim_trailing("]")
    |> String.split(", ")
    |> Enum.map(&parse_hint/1)
    |> Enum.join(" | ")
  end
  
  # Unknown types become term()
  def parse_hint(_unknown), do: "term()"
end
```

---

## Custom Type Definitions

Users can define custom type mappings:

```elixir
# config/autobridge.exs
config :autobridge, :type_mappings,
  sympy: %{
    "sympy.core.symbol.Symbol" => "atom()",
    "sympy.core.expr.Expr" => "expression()",
    "sympy.core.numbers.Integer" => "integer()",
    "sympy.core.numbers.Float" => "float()"
  },
  pylatexenc: %{
    "pylatexenc.latexwalker.LatexNode" => "latex_node()"
  }
```

---

## Type Generation

### Spec Generation

```elixir
defmodule AutoBridge.TypeGenerator do
  def generate_spec(function, inferred_types) do
    args = inferred_types.args
    |> Enum.map(&format_arg/1)
    |> Enum.join(", ")
    
    return = format_return(inferred_types.return)
    
    "@spec #{function}(#{args}) :: #{return}"
  end
  
  defp format_arg({name, type}) do
    "#{name} :: #{type}"
  end
  
  defp format_return({:ok_error, success_type}) do
    "{:ok, #{success_type}} | {:error, term()}"
  end
end
```

### Type Module Generation

For complex libraries, generate dedicated type modules:

```elixir
# Generated: lib/autobridge/types/sympy.ex
defmodule AutoBridge.Types.SymPy do
  @moduledoc "Type definitions for SymPy integration"
  
  @type expression :: String.t() | map()
  @type symbol :: atom()
  @type equation :: {:eq, expression(), expression()}
  @type solution :: [expression()]
  @type substitution :: %{symbol() => expression()}
  
  @type solve_error :: 
    {:no_solution, expression()} |
    {:invalid_expression, String.t()} |
    {:unsupported, String.t()}
end
```

---

## Serialization

### Python → Elixir

```elixir
defmodule AutoBridge.Serializer do
  @doc """
  Serialize Python objects for Elixir consumption.
  """
  
  # Standard JSON-compatible types pass through
  def serialize(value) when is_binary(value), do: value
  def serialize(value) when is_number(value), do: value
  def serialize(value) when is_boolean(value), do: value
  def serialize(nil), do: nil
  def serialize(value) when is_list(value) do
    Enum.map(value, &serialize/1)
  end
  def serialize(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {serialize(k), serialize(v)} end)
  end
  
  # Complex objects: convert to string representation
  def serialize({:python_object, type, repr}) do
    case serialization_strategy(type) do
      :string -> repr
      :structured -> parse_structured(repr)
      :custom -> apply_custom_serializer(type, repr)
    end
  end
end
```

### Elixir → Python

```elixir
defmodule AutoBridge.Deserializer do
  @doc """
  Prepare Elixir values for Python consumption.
  """
  
  def deserialize(value) when is_atom(value) do
    Atom.to_string(value)
  end
  
  def deserialize(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end
  
  def deserialize(value) when is_struct(value) do
    Map.from_struct(value)
  end
  
  def deserialize(value), do: value
end
```

---

## Error Type Mapping

### Python Exceptions → Elixir Errors

```elixir
@exception_mapping %{
  "TypeError" => :type_error,
  "ValueError" => :value_error,
  "KeyError" => :key_error,
  "IndexError" => :index_error,
  "AttributeError" => :attribute_error,
  "RuntimeError" => :runtime_error,
  "sympy.SympifyError" => :sympify_error,
  "sympy.SolveFailed" => :solve_failed
}

def map_exception(python_exception) do
  exception_type = python_exception["type"]
  message = python_exception["message"]
  
  elixir_error = Map.get(@exception_mapping, exception_type, :python_error)
  {:error, {elixir_error, message}}
end
```

---

## Dialyzer Integration

AutoBridge generates Dialyzer-compatible specs:

```elixir
# Generated wrapper with full specs
defmodule AutoBridge.SymPy do
  @moduledoc "Auto-generated SymPy wrapper"
  
  @type expression :: String.t() | map()
  @type symbol :: atom()
  
  @spec solve(expression(), symbol()) :: {:ok, [expression()]} | {:error, solve_error()}
  def solve(expr, var) do
    AutoBridge.Runtime.call(:sympy, :solve, [expr, var])
  end
  
  @spec simplify(expression()) :: {:ok, expression()} | {:error, term()}
  def simplify(expr) do
    AutoBridge.Runtime.call(:sympy, :simplify, [expr])
  end
end
```

---

## Escape Hatches

When type inference fails, provide escape hatches:

```elixir
# Override inferred type
AutoBridge.configure(:sympy, :solve, 
  return_type: "{:ok, [String.t()]} | {:error, solve_error()}"
)

# Skip type checking for complex function
AutoBridge.configure(:sympy, :complex_function,
  skip_typespec: true
)

# Use raw term() for unpredictable returns
# (Automatically applied when variance is too high)
```
