# Phase 1C: Executive Summary

**Cross-Ecosystem Analysis of Python Adapters for SnakeBridge**

---

## What We Analyzed

7 mature cross-language Python integration projects:

1. **PyO3** (Rust ↔ Python) - Trait-based elegance
2. **pyo3-asyncio** (Async Rust ↔ Python) - Async bridging
3. **JPype** (Java ↔ Python) - 20+ years of production lessons
4. **PyCall.jl** (Julia ↔ Python) - Zero-copy NumPy arrays
5. **reticulate** (R ↔ Python) - DataFrame interchange
6. **Apache Arrow** - Universal zero-copy data format
7. **gRPC** - Cross-language streaming patterns

---

## Key Findings (TL;DR)

### What Works

✅ **Trait/Protocol-Based Type Conversion** (PyO3)
- Extensible, user-friendly, compiler-verified
- Derive macros eliminate boilerplate
- Match quality levels for overload resolution

✅ **Customizer Pattern** (JPype)
- Opt-in behavior modification
- Type-specific enhancements
- Clear precedence rules

✅ **Zero-Copy via Arrow** (reticulate + Arrow)
- 10-100x faster for DataFrames/tensors
- Standardized memory layout
- Works across all languages

✅ **Separate Event Loops** (pyo3-asyncio)
- Don't merge async runtimes
- Explicit bridging via TaskLocals
- Python asyncio + Elixir BEAM coexist peacefully

✅ **Standardized Error Codes** (gRPC)
- Language-independent error semantics
- Structured error details
- Preserve stacktraces across boundaries

### What Doesn't Work

❌ **Automatic Type Coercion** (JPype lesson)
- Surprising behavior
- Hides intentional API design
- Make customizers opt-in

❌ **Hidden Memory Copies** (PyCall.jl lesson)
- Performance surprises
- Be explicit about copy vs. wrap
- Document costs

❌ **Merged Event Loops** (pyo3-asyncio lesson)
- Unnecessarily complex
- Run separate loops with bridges

❌ **Unclear Exception Handling** (Python C API)
- Silent failures
- Lost error context
- Make propagation explicit

---

## Proposed SnakeBridge Plugin Architecture

### Three Core Protocols

```elixir
# 1. Type Conversion (from PyO3)
defmodule SnakeBridge.TypeConverter do
  @callback from_python(term(), opts) :: {:ok, term()} | {:error, term()}
  @callback to_python(term(), opts) :: {:ok, term()} | {:error, term()}
  @callback match_quality(term()) :: :exact | :implicit | :explicit | :none
end

# 2. Module Customization (from JPype)
defmodule SnakeBridge.Customizer do
  @callback customize(module_ast, context) :: module_ast
  @callback priority() :: integer()
end

# 3. Lifecycle Hooks (from all projects)
defmodule SnakeBridge.Lifecycle do
  @callback on_session_start(session_id, config) :: :ok | {:error, term()}
  @callback on_instance_create(session_id, instance_ref, class) :: :ok
end
```

### Configuration Example

```elixir
config do
  %SnakeBridge.Config{
    python_module: "sklearn",

    plugins: %{
      # Zero-copy DataFrames via Arrow
      converters: [
        %{module: SnakeBridge.Converters.ArrowDataFrame, priority: 100}
      ],

      # Add Elixir-friendly methods
      customizers: [
        %{module: SnakeBridge.Customizers.DataFrame, applies_to: ["pandas.DataFrame"]}
      ],

      # Track model lifecycle
      lifecycle_hooks: [
        %{module: MyApp.ModelRegistry, events: ["instance_create"]}
      ]
    }
  }
end
```

### Generated Adapter

```elixir
defmodule Pandas.DataFrame do
  # Core methods from discovery
  def create(args), do: ...
  def head(df, n), do: ...

  # Customizer-added: Zero-copy conversion
  def to_explorer(df) do
    SnakeBridge.Converters.ArrowDataFrame.from_python(
      df.instance_ref,
      session_id: df.session_id
    )
  end

  # Customizer-added: Stream rows
  def stream_rows(df) do
    Stream.resource(...)
  end
end
```

---

## Immediate Recommendations

### Phase 1: Foundation (v0.3.0)

1. **Define TypeConverter behaviour** ✅ High Priority
   - `from_python/2`, `to_python/2`, `match_quality/1`
   - Built-in converters for primitives, collections
   - Registry in Config schema

2. **Implement Customizer pattern** ✅ High Priority
   - `customize/2` callback
   - Priority-based application
   - Per-class configuration

3. **Integrate Apache Arrow** ✅ Medium Priority
   - Add `arrow` dependency
   - DataFrame converter (Pandas ↔ Explorer)
   - Tensor converter (NumPy ↔ Nx)

4. **Standardize error handling** ✅ Medium Priority
   - Map gRPC codes to SnakeBridge.Error
   - Preserve Python stacktraces
   - Document error semantics

### Phase 2: Advanced (v0.4.0)

5. **Lifecycle hooks**
   - Session/instance events
   - User-defined cleanup
   - Metrics integration

6. **Async bridging**
   - Python AsyncIterator ↔ Elixir Stream
   - Streaming type converters
   - Context propagation

---

## Success Metrics

### Developer Experience

**Before (current)**:
```elixir
# Manual wrapper code
defmodule MyWrapper do
  def call_python(...) do
    # 50 lines of boilerplate
  end
end
```

**After (with plugins)**:
```elixir
# config/snakebridge/my_lib.exs
config do
  %SnakeBridge.Config{
    python_module: "my_lib",
    classes: [%{python_path: "my_lib.Model", elixir_module: MyLib.Model}]
  }
end

# Zero boilerplate, works immediately
{:ok, model} = MyLib.Model.create(%{...})
```

### Performance

**Target**: Match or exceed existing cross-language bridges

| Metric | Current (JSON) | Target (Arrow) | Improvement |
|--------|----------------|----------------|-------------|
| DataFrame transfer | 100 ms | 5 ms | **20x faster** |
| Tensor transfer | 500 ms | 10 ms | **50x faster** |
| Overhead | +10% | +2% | **5x reduction** |

### Extensibility

**Measure**: How easily can users add custom behavior?

- ✅ Define converter: 10 lines of code
- ✅ Add customizer: 15 lines of code
- ✅ Register lifecycle hook: 5 lines of code

---

## What Makes This Different

### vs. Raw Snakepit

| Feature | Raw Snakepit | SnakeBridge + Plugins |
|---------|-------------|----------------------|
| Type safety | Manual | Auto-generated specs |
| DataFrame transfer | JSON (slow) | Arrow (zero-copy) |
| Extensibility | Write wrapper code | Implement protocol |
| Async | gRPC streaming | Stream + AsyncIterator bridge |
| Error handling | gRPC codes | Structured SnakeBridge.Error |

### vs. Other Python Bridges

**SnakeBridge combines the best ideas from all 7 projects**:

- **PyO3's elegance** - Trait-based extensibility
- **JPype's maturity** - 20 years of lessons
- **Arrow's performance** - Zero-copy data
- **reticulate's flexibility** - Multiple environment strategies
- **gRPC's reliability** - Standardized streaming

**Unique to SnakeBridge**:
- **Config-driven** (not code-driven)
- **Elixir-native** (uses BEAM's strengths)
- **Discovery-first** (introspect then generate)
- **Telemetry-integrated** (observability built-in)

---

## Next Steps

1. **Review full analysis**: `docs/PHASE_1C_CROSS_ECOSYSTEM_ANALYSIS.md`
2. **Discuss priorities** with team
3. **Plan v0.3.0 sprint**: TypeConverter + Customizer implementation
4. **Benchmark Arrow integration**: Prove 20x performance claim
5. **Write guides**: "Writing Custom Converters", "Creating Customizers"

---

## Conclusion

After analyzing 100+ years of combined cross-language integration experience, three patterns emerge as essential:

1. **Extensibility through protocols** (not inheritance)
2. **Zero-copy for data** (via shared standards like Arrow)
3. **Explicit over implicit** (clarity beats cleverness)

SnakeBridge is uniquely positioned to learn from these mature projects while leveraging Elixir's strengths (processes, pattern matching, macros) to create the most elegant Python integration layer yet.

**Vision**: Make Python integration in Elixir as natural as using native Elixir libraries.

---

**Document**: Phase 1C Executive Summary
**Full Analysis**: `docs/PHASE_1C_CROSS_ECOSYSTEM_ANALYSIS.md` (15,000+ words)
**Date**: November 26, 2025
