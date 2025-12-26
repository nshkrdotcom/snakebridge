# Agentic Workflows

## Purpose

SnakeBridge should be usable by AI agents and automation without extra glue. This document describes APIs that let agents explore, discover, and use Python libraries programmatically.

## The Agent Problem

AI agents need to:
1. **Discover** available APIs without prior knowledge
2. **Understand** function signatures and types
3. **Generate** adapters on-demand
4. **Call** functions safely with structured errors

Traditional full-library generation is too slow for iterative agent loops. SnakeBridge's lazy architecture solves this naturally.

## Discovery APIs

### List Libraries

```elixir
SnakeBridge.list_libraries()
# => [:numpy, :pandas, :sympy]
```

### List Functions

```elixir
Numpy.__functions__()
# => [
#   {:array, 1, Numpy, "Create an array."},
#   {:mean, 1, Numpy, "Compute the arithmetic mean..."},
#   ...
# ]
```

### Search

```elixir
Numpy.__search__("matrix multiply")
# => [
#   %{name: :matmul, summary: "Matrix product of two arrays.", relevance: 0.95},
#   %{name: :dot, summary: "Dot product of two arrays.", relevance: 0.87}
# ]
```

### Get Signature

```elixir
SnakeBridge.signature(Numpy, :array)
# => %{
#   name: :array,
#   parameters: [
#     %{name: "object", required: true},
#     %{name: "dtype", required: false, default: "None"}
#   ],
#   return_type: "ndarray"
# }
```

## On-Demand Generation

```elixir
# Ensure adapter exists before calling
SnakeBridge.ensure_adapter(Numpy, :array)
# => :ok (generates if needed, no-op if exists)

# Then call safely
Numpy.array([1, 2, 3])
# => {:ok, [1, 2, 3]}
```

### Batch Generation

```elixir
SnakeBridge.ensure_adapters([
  {Numpy, :array},
  {Numpy, :dot},
  {Pandas, :DataFrame}
])
# => :ok
```

`ensure_adapter/2` runs the **same prepass generator** as `mix compile`, writes to `lib/snakebridge_generated/`, and compiles the updated library file in the current VM. In strict mode, it returns an error instead of generating.

## Strict Mode Interaction

With `strict: true`, `ensure_adapter/2` fails instead of generating:

```elixir
# In production/CI
config :snakebridge, strict: true

SnakeBridge.ensure_adapter(Numpy, :new_function)
# => {:error, :strict_mode, "Cannot generate in strict mode. Add to manifest first."}
```

Agents should:
1. Run in non-strict dev mode to discover and generate
2. Commit generated source
3. Deploy with strict mode

## Dynamic Call Ledger

For calls that can't be statically analyzed:

```elixir
# Dynamic call (recorded to ledger in dev)
SnakeBridge.Runtime.dynamic_call(Numpy, :custom_op, [a, b, c])
```

After development:

```bash
$ mix snakebridge.ledger
Dynamic calls detected:
  Numpy.custom_op/3 - called 5 times

$ mix snakebridge.promote
Promoting to manifest...
Done. Commit the changes.
```

## Example Agent Loop

```elixir
defmodule MyAgent do
  @doc """
  Agent loop for exploring and using Python libraries.
  """
  def execute_task(task) do
    # 1. Search for relevant functions
    candidates = search_for_task(task)
    
    # 2. Get details for top candidates
    detailed = Enum.map(candidates, fn func ->
      %{
        name: func.name,
        doc: Numpy.doc(func.name),
        sig: SnakeBridge.signature(Numpy, func.name)
      }
    end)
    
    # 3. Select best function
    selected = select_best(detailed, task)
    
    # 4. Ensure adapter exists
    :ok = SnakeBridge.ensure_adapter(Numpy, selected.name)
    
    # 5. Build arguments and call
    args = build_args(selected, task)
    apply(Numpy, selected.name, args)
  end

  defp search_for_task(task) do
    keywords = extract_keywords(task)
    
    SnakeBridge.list_libraries()
    |> Enum.flat_map(fn lib ->
      module = SnakeBridge.module_for(lib)
      module.__search__(keywords)
    end)
    |> Enum.sort_by(& &1.relevance, :desc)
    |> Enum.take(5)
  end
end
```

## Safety and Guardrails

### Library Allowlist

Only configured libraries can be accessed:

```elixir
# mix.exs
{:snakebridge, libraries: [numpy: "~> 1.26"]}

# Allowed
SnakeBridge.ensure_adapter(Numpy, :array)

# Not allowed (library not configured)
SnakeBridge.ensure_adapter(Os, :system)
# => {:error, :library_not_configured, "os"}
```

### Rate Limiting

```elixir
config :snakebridge,
  agent: [
    rate_limit: 100,    # calls per second
    timeout: 5000       # ms per call
  ]
```

### Structured Errors

```elixir
case Numpy.nonexistent([1, 2, 3]) do
  {:ok, result} ->
    result

  {:error, %SnakeBridge.Error{
    type: :function_not_found,
    message: "Function 'nonexistent' not found in numpy",
    suggestions: [:array, :zeros, :ones]
  }} ->
    # Agent can retry with suggestions
end
```

## Deterministic Behavior

Agent-friendly APIs are designed for predictable behavior:

| Operation | Behavior |
|-----------|----------|
| `ensure_adapter/2` | Idempotent (safe to call multiple times) |
| `__search__/1` | Stable results (same query = same results) |
| Error returns | Well-defined, parseable types |
| Discovery | Read-only, no side effects |

## Programmatic Spec Generation

For agents that know what they need:

```elixir
# Generate from a spec
SnakeBridge.generate_from_spec(%{
  numpy: [:array, :zeros, :dot, :matmul],
  pandas: [:DataFrame, :read_csv]
})
# => :ok
```

## Integration with Snakepit

For long-running agent tasks, use Snakepit sessions:

```elixir
# Session affinity for stateful operations
{:ok, _} = Snakepit.execute_in_session("agent_session", "load_model", %{})
{:ok, result} = Snakepit.execute_in_session("agent_session", "predict", %{data: input})
```

SnakeBridge generates the typed wrappers; Snakepit handles session management.
