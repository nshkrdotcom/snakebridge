## Comparison: SnakeBridge v3 vs. Snakepit Lazy Ecosystem

### Structural Overview

| Aspect | SnakeBridge v3 | Snakepit Lazy |
|--------|----------------|---------------|
| **Architecture** | Single package (SnakeBridge) | Two-layer (Snakepit runtime + Snakebridge codegen) |
| **Maturity** | Implementation-ready with code | Vision-focused, abstract |
| **Config Location** | `{:snakebridge, libraries: [...]}` | `{:snakepit, snakebridge: [...]}` |
| **Execution Model** | Pre-pass only (decisive) | Pre-pass default, tracer "experimental" |
| **Engineering Rationale** | Dedicated decisions doc | Scattered across files |
| **Migration Path** | Detailed v2→v3 guide | None |

### Where SnakeBridge v3 Excels

**1. Architectural Clarity**

The single-package model eliminates cognitive overhead. Configuration lives directly in the dependency declaration:

```elixir
{:snakebridge, "~> 3.0",
 libraries: [numpy: "~> 1.26", sympy: "~> 1.12"]}
```

versus the nested approach:

```elixir
{:snakepit, "~> 0.4.0",
 snakebridge: [
   libraries: [sympy: "1.12"],
   lazy_generation: :on,
   docs: :on_demand
 ]}
```

The first is declarative and obvious. The second forces users to understand a two-layer architecture they don't need to care about.

**2. Decisive Engineering**

Document 11 (Engineering Decisions) is exceptional. It doesn't just describe what the system does—it explains what was rejected and why. The comparison table on mid-compilation injection vs. pre-pass generation is exactly the kind of analysis that prevents future architectural drift:

> "The mid-compilation injection approach has several fatal flaws... Compilation Concurrency, Incremental Compilation Confusion, Tooling Incompatibility..."

The Snakepit docs hedge with "a tracer-based approach remains an optional future experiment." This hedging invites scope creep.

**3. Implementation Depth**

SnakeBridge v3 has actual code for every component:
- Scanner implementation with AST walking
- Introspector with Python script templates
- Generator with atomic file writes
- Manifest and lock file schemas
- Mix compiler task integration

Snakepit Lazy has concepts but no implementation artifacts. You could start building from SnakeBridge v3 today.

**4. Determinism Strategy**

Both have lockfiles, but SnakeBridge v3's is fully specified:

```json
{
  "environment": {
    "snakebridge_version": "3.0.0",
    "python_version": "3.11.5",
    "platform": "linux-x86_64"
  },
  "libraries": {
    "numpy": {
      "requested": "~> 1.26",
      "resolved": "1.26.4",
      "checksum": "sha256:abc123..."
    }
  }
}
```

The Snakepit version is described in prose but never shown concretely.

**5. Migration Story**

A migration guide exists. This matters for adoption. Snakepit Lazy assumes greenfield.

### Where Snakepit Lazy Has Value

**1. RST/Math Rendering Awareness**

The docs-experience.md acknowledges a real problem:

> "Python docstrings are usually reStructuredText, not Markdown. The rendering pipeline should be: Parse RST to HTML using docutils (Python), Convert to Markdown only if ExDoc requires it, Escape only unsafe HTML, never raw code blocks or backticks."

SnakeBridge v3's docs system doesn't address this. For SymPy (heavy math notation) this is critical.

**2. Dynamic Call Ledger Workflow**

Snakepit Lazy has a clearer mental model for dynamic dispatch:

```elixir
Snakepit.dynamic_call(:sympy, :integrate, [expr, x])
```

Plus explicit promotion: `mix snakepit.promote_ledger`

SnakeBridge v3 has this concept but it's buried in the engineering decisions doc rather than surfaced as a first-class workflow.

**3. UX Journeys Document**

The ux-journeys.md frames the system from developer emotions:

> "Expected feelings: 'I did not need to touch Python.' 'It just works with a few lines of config.'"

This is useful for evaluating design decisions against real user outcomes.

**4. Open Questions Acknowledgment**

Snakepit Lazy explicitly lists what's unresolved:

> "What is the best RST to HTML/Markdown conversion pipeline for docstrings?"
> "How should we handle optional dependencies that change the available API surface?"

SnakeBridge v3 reads as complete, but these questions still apply.

---

## Decision: SnakeBridge v3 is the Better Design

The SnakeBridge v3 architecture is superior because:

1. **It's buildable today** — implementation artifacts exist
2. **It's decisively scoped** — no "experimental future" escape hatches
3. **It has a migration path** — critical for adoption
4. **It's architecturally cleaner** — single package, clear responsibility
5. **It explains itself** — engineering decisions are documented

The Snakepit Lazy documents read like an earlier design phase that was superseded. The two-layer architecture (Snakepit + Snakebridge) adds complexity without clear benefit.

---

## Enhancements for SnakeBridge v3

### From Snakepit Lazy

1. **RST/Math Rendering Pipeline** (docs-experience.md)
   
   Add to 05-documentation-system.md:
   - RST to HTML via `docutils` (Python-side)
   - Math rendering via KaTeX integration
   - Explicit escape policy (preserve code blocks)

2. **First-Class Dynamic Call API**
   
   Surface the ledger workflow more prominently:
   ```elixir
   # Explicit dynamic call (records to ledger in dev)
   SnakeBridge.dynamic_call(Numpy, :custom_op, [a, b, c])
   
   # Promote ledger to manifest
   $ mix snakebridge.ledger.promote
   ```

3. **UX Journey Framing**
   
   Add a document or section describing the emotional arc:
   - Fresh project (60 seconds to first call)
   - Exploration (search → docs → call)
   - Growth (incremental, stable diffs)
   - Cleanup (explicit, controlled)

4. **Open Questions Document**
   
   Acknowledge unknowns explicitly rather than presenting as complete:
   - Type mapping strategy for complex objects (DataFrame, NDArray)
   - Optional dependency handling (torch+cuda vs torch)
   - Editor/LSP integration depth

### Original Enhancements

5. **Parallel Introspection**
   
   The introspector batches within a library but could parallelize across libraries:
   ```elixir
   Task.async_stream(libraries, &introspect_library/1, max_concurrency: 4)
   ```

6. **Warm Cache Distribution**
   
   Add mechanism to export/import generated source for team sharing:
   ```bash
   $ mix snakebridge.cache.export --output cache.tar.gz
   $ mix snakebridge.cache.import cache.tar.gz
   ```
   
   This exists in 07-developer-experience.md but deserves its own section in the architecture docs.

7. **Typespec Generation Strategy**
   
   The generated code shows `@spec` but doesn't detail how types are inferred:
   - Python type hints → Elixir typespecs
   - NumPy dtype mapping
   - Return type inference from introspection

8. **Error Recovery in Generation**
   
   What happens when Python introspection fails mid-batch?
   - Skip failed symbols with warning?
   - Fail entire library?
   - Retry with backoff?

9. **IDE Plugin Specification**
   
   Section 07 mentions VS Code/Vim/Emacs plugins but doesn't specify the protocol. Define:
   - What data the plugin needs (symbol list, signatures, docs)
   - How to expose it (JSON over stdio? LSP extension?)

10. **Benchmark Targets**
    
    Add concrete performance targets:
    - First compile with 10 functions: <500ms
    - First compile with 100 functions: <3s
    - Incremental with no changes: <100ms
    - Doc query (cached): <10ms
    - Doc query (Python): <100ms

11. **Submodule Handling Detail**
    
    The docs mention `numpy.linalg.solve → Numpy.Linalg.solve` but don't detail:
    - When are submodules separate files vs. nested in parent?
    - How deep does introspection go?
    - How are circular imports detected and handled?

12. **Test Mocking Strategy**
    
    Section 07 shows mock setup but could be more comprehensive:
    - How to mock at the protocol level (not just function replacement)
    - Integration with ExUnit's async tests
    - Snapshot testing for generated source
