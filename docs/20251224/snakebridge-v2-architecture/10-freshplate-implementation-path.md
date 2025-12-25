# SnakeBridge v2: Fresh Plate Implementation Path

**Date**: 2025-12-24
**Status**: Implementation Roadmap
**Premise**: Build from scratch using insights from v1, not refactoring v1

---

## Core Philosophy

> "The right way to build v2 is not to refactor v1, but to write the code you wish v1 had been."

This document assumes we **delete everything** and start fresh with only Snakepit as a dependency.

---

## Final Directory Structure

```
snakebridge/
├── lib/
│   ├── snakebridge.ex                    # 50 lines - public API
│   ├── snakebridge/
│   │   ├── runtime.ex                    # 100 lines - Snakepit wrapper
│   │   ├── types/
│   │   │   ├── encoder.ex                # 150 lines - Elixir → JSON
│   │   │   └── decoder.ex                # 150 lines - JSON → Elixir
│   │   ├── generator/
│   │   │   ├── introspector.ex           # 100 lines - shell out to Python
│   │   │   ├── type_mapper.ex            # 200 lines - Python types → @spec
│   │   │   ├── doc_formatter.ex          # 150 lines - docstring → @doc
│   │   │   └── source_writer.ex          # 250 lines - AST → .ex source
│   │   └── adapters/                     # GENERATED
│   │       ├── numpy.ex
│   │       ├── json.ex
│   │       └── ...
│   └── mix/
│       └── tasks/
│           └── snakebridge/
│               └── gen.ex                # 80 lines - mix task
├── priv/
│   └── python/
│       ├── introspect.py                 # 200 lines - introspection script
│       └── snakebridge_types.py          # 100 lines - type encoding
├── test/
│   ├── snakebridge_test.exs
│   ├── types/
│   │   ├── encoder_test.exs
│   │   └── decoder_test.exs
│   └── generator/
│       └── type_mapper_test.exs
├── mix.exs
└── README.md

Estimated total: ~1,500 lines of Elixir + ~300 lines Python
(vs current ~8,000+ lines)
```

---

## Implementation Order

### Step 1: Minimal Runtime (Day 1)

Create the thinnest possible wrapper around Snakepit.

**`lib/snakebridge.ex`**
```elixir
defmodule SnakeBridge do
  @moduledoc """
  SnakeBridge - Elixir bindings for Python libraries.
  """

  alias SnakeBridge.Runtime

  @doc "Call a Python function"
  defdelegate call(module, function, args \\ %{}, opts \\ []), to: Runtime

  @doc "Stream from a Python generator"
  defdelegate stream(module, function, args \\ %{}, opts \\ []), to: Runtime
end
```

**`lib/snakebridge/runtime.ex`**
```elixir
defmodule SnakeBridge.Runtime do
  @moduledoc false

  alias SnakeBridge.Types.{Encoder, Decoder}

  def call(module, function, args, opts \\ []) do
    encoded_args = Encoder.encode(args)

    case Snakepit.execute(
      "snakebridge_call",
      %{module: module, function: function, args: encoded_args},
      opts
    ) do
      {:ok, %{"success" => true, "result" => result}} ->
        {:ok, Decoder.decode(result)}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, _} = error ->
        error
    end
  end

  def stream(module, function, args, opts \\ []) do
    encoded_args = Encoder.encode(args)

    Snakepit.execute_stream(
      "snakebridge_stream",
      %{module: module, function: function, args: encoded_args},
      opts
    )
    |> Stream.map(&Decoder.decode/1)
  end
end
```

**Python side: `priv/python/snakebridge_adapter.py`**
```python
def snakebridge_call(module: str, function: str, args: dict) -> dict:
    """Execute a Python function and return result."""
    try:
        mod = importlib.import_module(module)
        func = getattr(mod, function)
        result = func(**args)
        return {"success": True, "result": encode(result)}
    except Exception as e:
        return {"success": False, "error": str(e)}
```

---

### Step 2: Type System (Day 1-2)

The heart of the system - lossless type conversion.

**`lib/snakebridge/types/encoder.ex`**
```elixir
defmodule SnakeBridge.Types.Encoder do
  @moduledoc "Encode Elixir values to tagged JSON for Python"

  def encode(value) when is_tuple(value) do
    %{"__type__" => "tuple", "elements" => Tuple.to_list(value) |> Enum.map(&encode/1)}
  end

  def encode(%MapSet{} = set) do
    %{"__type__" => "set", "elements" => MapSet.to_list(set) |> Enum.map(&encode/1)}
  end

  def encode(value) when is_binary(value) and not is_bitstring(value) do
    if String.valid?(value) do
      value  # UTF-8 string
    else
      %{"__type__" => "bytes", "encoding" => "base64", "data" => Base.encode64(value)}
    end
  end

  def encode(%DateTime{} = dt), do: %{"__type__" => "datetime", "iso" => DateTime.to_iso8601(dt)}
  def encode(%Date{} = d), do: %{"__type__" => "date", "iso" => Date.to_iso8601(d)}
  def encode(%Time{} = t), do: %{"__type__" => "time", "iso" => Time.to_iso8601(t)}

  def encode(:infinity), do: %{"__type__" => "float", "value" => "Infinity"}
  def encode(:neg_infinity), do: %{"__type__" => "float", "value" => "-Infinity"}
  def encode(:nan), do: %{"__type__" => "float", "value" => "NaN"}

  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)

  def encode(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {to_string(k), encode(v)} end)
  end

  def encode(value) when is_atom(value), do: to_string(value)
  def encode(value), do: value  # int, float, bool, nil pass through
end
```

**`lib/snakebridge/types/decoder.ex`**
```elixir
defmodule SnakeBridge.Types.Decoder do
  @moduledoc "Decode tagged JSON from Python to Elixir values"

  def decode(%{"__type__" => "tuple", "elements" => elements}) do
    elements |> Enum.map(&decode/1) |> List.to_tuple()
  end

  def decode(%{"__type__" => "set", "elements" => elements}) do
    elements |> Enum.map(&decode/1) |> MapSet.new()
  end

  def decode(%{"__type__" => "bytes", "encoding" => "base64", "data" => data}) do
    Base.decode64!(data)
  end

  def decode(%{"__type__" => "datetime", "iso" => iso}) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    dt
  end

  def decode(%{"__type__" => "date", "iso" => iso}), do: Date.from_iso8601!(iso)
  def decode(%{"__type__" => "time", "iso" => iso}), do: Time.from_iso8601!(iso)

  def decode(%{"__type__" => "float", "value" => "Infinity"}), do: :infinity
  def decode(%{"__type__" => "float", "value" => "-Infinity"}), do: :neg_infinity
  def decode(%{"__type__" => "float", "value" => "NaN"}), do: :nan

  def decode(%{"__type__" => "complex", "real" => r, "imag" => i}), do: {:complex, r, i}

  def decode(list) when is_list(list), do: Enum.map(list, &decode/1)

  def decode(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, decode(v)} end)
  end

  def decode(value), do: value
end
```

**Test file: `test/types/encoder_test.exs`**
```elixir
defmodule SnakeBridge.Types.EncoderTest do
  use ExUnit.Case
  alias SnakeBridge.Types.{Encoder, Decoder}

  test "round-trip tuple" do
    original = {:ok, "value", 42}
    encoded = Encoder.encode(original)
    decoded = Decoder.decode(encoded)
    assert decoded == original
  end

  test "round-trip MapSet" do
    original = MapSet.new([1, 2, 3])
    encoded = Encoder.encode(original)
    decoded = Decoder.decode(encoded)
    assert decoded == original
  end

  test "round-trip binary" do
    original = <<0, 1, 2, 255>>
    encoded = Encoder.encode(original)
    decoded = Decoder.decode(encoded)
    assert decoded == original
  end

  test "round-trip DateTime" do
    original = ~U[2024-12-24 12:00:00Z]
    encoded = Encoder.encode(original)
    decoded = Decoder.decode(encoded)
    assert decoded == original
  end

  test "infinity/nan atoms" do
    assert Decoder.decode(Encoder.encode(:infinity)) == :infinity
    assert Decoder.decode(Encoder.encode(:neg_infinity)) == :neg_infinity
    assert Decoder.decode(Encoder.encode(:nan)) == :nan
  end
end
```

---

### Step 3: Python Introspection Script (Day 2)

**`priv/python/introspect.py`** - Full implementation in synthesis doc.

Key features:
- `inspect.signature()` for all functions
- `typing.get_type_hints()` with fallbacks
- `docstring_parser` for structured docs
- Output JSON to stdout

Test it standalone:
```bash
python priv/python/introspect.py json > test_output.json
```

---

### Step 4: Elixir Generator (Day 2-3)

**`lib/snakebridge/generator/introspector.ex`**
```elixir
defmodule SnakeBridge.Generator.Introspector do
  @moduledoc "Run Python introspection and parse results"

  def introspect(library) do
    script = Path.join(:code.priv_dir(:snakebridge), "python/introspect.py")

    case System.cmd("python3", [script, library], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {error, code} ->
        {:error, "Introspection failed (exit #{code}): #{error}"}
    end
  end
end
```

**`lib/snakebridge/generator/type_mapper.ex`**
```elixir
defmodule SnakeBridge.Generator.TypeMapper do
  @moduledoc "Convert Python type dicts to Elixir @spec AST"

  def to_spec(%{"kind" => "primitive", "name" => "int"}), do: quote(do: integer())
  def to_spec(%{"kind" => "primitive", "name" => "float"}), do: quote(do: float())
  def to_spec(%{"kind" => "primitive", "name" => "str"}), do: quote(do: String.t())
  def to_spec(%{"kind" => "primitive", "name" => "bool"}), do: quote(do: boolean())
  def to_spec(%{"kind" => "primitive", "name" => "bytes"}), do: quote(do: binary())
  def to_spec(%{"kind" => "none"}), do: quote(do: nil)
  def to_spec(%{"kind" => "any"}), do: quote(do: any())

  def to_spec(%{"kind" => "list", "element" => el}) do
    inner = to_spec(el)
    quote(do: [unquote(inner)])
  end

  def to_spec(%{"kind" => "tuple", "elements" => els}) do
    inner = Enum.map(els, &to_spec/1)
    {:{}, [], inner}
  end

  def to_spec(%{"kind" => "dict", "key" => k, "value" => v}) do
    key_spec = to_spec(k)
    val_spec = to_spec(v)
    quote(do: %{unquote(key_spec) => unquote(val_spec)})
  end

  def to_spec(%{"kind" => "set", "element" => el}) do
    inner = to_spec(el)
    quote(do: MapSet.t(unquote(inner)))
  end

  def to_spec(%{"kind" => "union", "types" => types}) do
    types
    |> Enum.map(&to_spec/1)
    |> Enum.reduce(fn t, acc -> quote(do: unquote(acc) | unquote(t)) end)
  end

  def to_spec(%{"kind" => "class", "name" => name}) do
    # For known classes, map to appropriate type
    case name do
      "ndarray" -> quote(do: map())  # NumPy array as map
      "DataFrame" -> quote(do: map())  # Pandas DataFrame
      _ -> quote(do: any())
    end
  end

  def to_spec(_), do: quote(do: any())
end
```

**`lib/snakebridge/generator/source_writer.ex`** (key function):
```elixir
defmodule SnakeBridge.Generator.SourceWriter do
  alias SnakeBridge.Generator.{TypeMapper, DocFormatter}

  def generate(introspection, opts \\ []) do
    module_name = opts[:module] || default_module_name(introspection["name"])
    functions = introspection["functions"] || []

    module_ast = build_module_ast(module_name, introspection, functions)

    module_ast
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> prepend_header()
  end

  defp build_module_ast(module_name, intro, functions) do
    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(DocFormatter.module_doc(intro))

        alias SnakeBridge.{Runtime, Types}

        unquote_splicing(Enum.map(functions, &build_function_ast(intro["name"], &1)))
      end
    end
  end

  defp build_function_ast(python_module, func) do
    name = String.to_atom(func["name"])
    doc = DocFormatter.function_doc(func)
    spec = build_spec(func)
    body = build_body(python_module, func)

    quote do
      @doc unquote(doc)
      @spec unquote(spec)
      unquote(body)
    end
  end

  # ... more implementation
end
```

---

### Step 5: Mix Task (Day 3)

**`lib/mix/tasks/snakebridge/gen.ex`**
```elixir
defmodule Mix.Tasks.Snakebridge.Gen do
  use Mix.Task

  @shortdoc "Generate Elixir adapter for a Python library"

  def run(args) do
    {opts, [library], _} = OptionParser.parse(args,
      strict: [output: :string, module: :string, force: :boolean])

    Mix.shell().info("Introspecting #{library}...")

    case SnakeBridge.Generator.Introspector.introspect(library) do
      {:ok, introspection} ->
        source = SnakeBridge.Generator.SourceWriter.generate(introspection, opts)
        output_path = opts[:output] || "lib/snakebridge/adapters/#{library}.ex"

        File.mkdir_p!(Path.dirname(output_path))
        File.write!(output_path, source)

        Mix.shell().info("✓ Generated #{output_path}")
        Mix.shell().info("  #{length(introspection["functions"] || [])} functions")

      {:error, reason} ->
        Mix.shell().error("Failed: #{reason}")
        exit({:shutdown, 1})
    end
  end
end
```

---

### Step 6: Generate Adapters (Day 3-4)

```bash
# Generate standard library adapters
mix snakebridge.gen json
mix snakebridge.gen base64
mix snakebridge.gen hashlib
mix snakebridge.gen re

# Generate popular library adapters
mix snakebridge.gen numpy
mix snakebridge.gen requests
mix snakebridge.gen pandas
```

Each generates a fully-documented `.ex` file.

---

### Step 7: Documentation & Tests (Day 4-5)

1. Write README with usage examples
2. Add `@moduledoc` and `@doc` to all modules
3. Integration tests for generated adapters
4. ExDoc configuration for HexDocs

---

## Key Design Decisions

### 1. No Runtime Manifest Loading
- All code generation is offline via `mix snakebridge.gen`
- Generated files are committed to git
- No runtime JSON parsing or module compilation

### 2. No Allowlist/Registry
- If you generate an adapter, you trust it
- Security is at the generation step, not runtime
- Python sandboxing is Snakepit's job

### 3. No Config Struct
- Use plain maps from JSON introspection
- Structs add complexity without benefit here

### 4. No Hooks/Callbacks
- Generated code is static Elixir
- Customization via fork/edit, not runtime hooks

### 5. Tagged Types Are Non-Negotiable
- Every non-primitive needs `__type__` tag
- Enables perfect round-tripping
- Makes debugging easier (can see types in JSON)

---

## Migration from v1

For existing v1 users:

1. **Remove all runtime manifest loading**
   - Delete `config :snakebridge, load: [...]`

2. **Generate adapters**
   ```bash
   mix snakebridge.gen numpy
   mix snakebridge.gen json
   # etc.
   ```

3. **Update imports**
   ```elixir
   # Old
   SnakeBridge.call("json", "dumps", %{obj: data})

   # New
   SnakeBridge.Json.dumps(data)
   ```

4. **Handle type changes**
   - Tuples now stay tuples (not converted to lists)
   - Sets are MapSet (not lists)
   - Bytes are binaries (not base64 strings in maps)

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Total LoC (excluding generated) | < 1,500 |
| Module count | < 15 |
| `mix snakebridge.gen numpy` time | < 5 seconds |
| Generated adapter LoC (numpy) | ~2,000 |
| HexDocs quality | Professional |
| Dialyzer warnings | 0 |
| Test coverage | > 90% |

---

## What NOT To Build

To keep scope minimal:

1. **No streaming generation** - Generate whole file at once
2. **No incremental updates** - Regenerate whole file
3. **No caching** - Let Snakepit handle it
4. **No config files** - CLI args only
5. **No plugin system** - Fork if you need custom
6. **No AI assistance** - Deterministic introspection only
7. **No backwards compatibility** - Clean break from v1

---

## Next Steps

1. Create fresh git branch `v2-fresh`
2. Delete all lib/ content
3. Implement Step 1 (minimal runtime)
4. Write tests for Step 2 (types)
5. Iterate through steps 3-7

Estimated timeline: 1 week for feature-complete, 1 more week for polish.
