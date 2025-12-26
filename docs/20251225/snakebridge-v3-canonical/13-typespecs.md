# Typespecs and Type Mapping

## Purpose

SnakeBridge v3 generates `@spec` annotations from Python type hints. The goal is **useful** (not perfect) typespecs that improve IDE hints and Dialyzer feedback without breaking compilation.

## Core Types

These runtime handle types are defined in Snakepit Prime and referenced by
SnakeBridge-generated specs.

Runtime errors use `Snakepit.Error.t()` and subtypes; SnakeBridge does not
wrap or redefine these errors.

### Python Object References

Python objects that cannot be safely serialized are represented as opaque references:

```elixir
@type Snakepit.PyRef.t :: %Snakepit.PyRef{
  ref: reference(),          # runtime handle
  library: String.t(),       # "numpy", "sympy", ...
  class: String.t() | nil    # "ndarray", "Symbol", ...
}
```

Instances of Python classes and complex objects (e.g., `numpy.ndarray`) map to `Snakepit.PyRef.t()` unless a library defines a custom Elixir struct.

### Zero-Copy Handles

Zero-copy interop uses explicit handle types:

```elixir
@type Snakepit.ZeroCopyRef.t :: %Snakepit.ZeroCopyRef{
  kind: :dlpack | :arrow,
  device: :cpu | :cuda | :mps,
  dtype: atom(),
  shape: tuple() | nil
}
```

These handles are passed to generated functions and unwrapped in Python via the Snakepit adapter.

## Mapping Table

| Python Annotation | Elixir Typespec |
|-------------------|-----------------|
| `int` | `integer()` |
| `float` | `float()` |
| `str` | `String.t()` |
| `bool` | `boolean()` |
| `bytes` | `binary()` |
| `None` | `nil` |
| `list[T]` | `list(t)` |
| `tuple[T1, T2]` | `{t1, t2}` |
| `dict[K, V]` | `%{optional(k) => v}` |
| `set[T]` | `MapSet.t(t)` |
| `Iterable[T]` | `Enumerable.t()` or `list(t)` |
| `Optional[T]` | `t | nil` |
| `Union[A, B]` | `a | b` |
| `Any` | `term()` |
| `Callable` | `function()` |
| `numpy.ndarray` | `Snakepit.PyRef.t()` |
| Unknown | `term()` |

`T`, `K`, and `V` are recursively mapped.

## Generics and Unions

- `Union` and `Optional` map to Elixir union types.
- Deep generic chains collapse to `term()` if ambiguity is too high.
- Forward references are left as `term()` unless the class is also generated.

## Class Types

If the class is generated, we prefer a module-specific type:

```elixir
@spec new(term()) :: {:ok, Sympy.Symbol.t()} | {:error, Snakepit.Error.t()}
```

If not generated, fall back to `Snakepit.PyRef.t()`.

## Keyword Arguments

Generated functions use `keyword()` for optional/keyword-only args:

```elixir
@spec mean(term(), keyword()) :: {:ok, term()} | {:error, Snakepit.Error.t()}
```

When there are no optional/keyword args, the `keyword()` parameter is omitted.

## Examples

### Simple Function

```elixir
@spec sqrt(number()) :: {:ok, float()} | {:error, Snakepit.Error.t()}
```

### Class Method

```elixir
@spec simplify(Snakepit.PyRef.t(), keyword()) :: {:ok, Snakepit.PyRef.t()} | {:error, Snakepit.Error.t()}
```

## Limitations

- Python type hints are not always accurate or complete.
- Some libraries expose types via strings or custom wrappers.
- The mapping prioritizes **safety** over precision.

Future versions can add library-specific type plug-ins for richer specs.
