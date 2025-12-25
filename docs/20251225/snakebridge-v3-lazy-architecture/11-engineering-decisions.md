# Engineering Decisions

This document captures critical design decisions, the alternatives considered, and the rationale for each choice. These decisions address fundamental engineering challenges that determine whether v3 actually works or remains a "nice dream."

---

## Decision 1: Pre-Pass Generation vs. Mid-Compilation Injection

### The Question

How do we integrate lazy generation into the Elixir compilation process?

### Options Considered

**Option A: Compiler Tracer with Mid-Compilation Injection**
- Hook into Elixir's compilation tracer
- Intercept undefined remote function calls
- Generate code and inject it "just in time"
- Resume compilation with newly available code

**Option B: Pre-Pass AST Scanning with Source Generation**
- Run a separate compiler task BEFORE Elixir compilation
- Scan project source for library calls
- Generate `.ex` files to `lib/snakebridge_generated/`
- Let normal Elixir compilation proceed

### Decision: Option B (Pre-Pass Generation)

### Rationale

The mid-compilation injection approach has several fatal flaws:

1. **Compilation Concurrency**: Mix/Elixir can compile files in parallel. Injecting modules mid-flight requires complex locking and can cause race conditions where partially-defined modules are accessed.

2. **Incremental Compilation Confusion**: "I changed file A, why did module B regenerate?" becomes a recurring issue when generation is triggered by tracing rather than explicit pre-pass.

3. **Tooling Incompatibility**: Dialyzer, ExDoc, language servers, and editor "go to definition" expect code to exist as source files before compilation. Mid-injection breaks these assumptions.

4. **Hot Code Loading Semantics**: Adding functions to already-loaded modules during compilation is non-standard behavior that will surprise developers and complicate debugging.

5. **The Elixir Compiler is Aggressive**: Standard tracers report on compilation events; they don't easily support "pause, generate, inject, resume" without fighting the compiler's design.

The pre-pass model sidesteps all these issues by generating real `.ex` source files that the Elixir compiler processes normally. This preserves:
- Dialyzer compatibility
- ExDoc compatibility
- IDE "go to definition"
- Normal debugging
- Deterministic builds

### Implementation

```elixir
# mix.exs - Compiler order
def project do
  [
    compilers: [:snakebridge] ++ Mix.compilers()  # SnakeBridge runs FIRST
  ]
end
```

```elixir
# lib/mix/tasks/compile/snakebridge.ex
defmodule Mix.Tasks.Compile.Snakebridge do
  use Mix.Task.Compiler

  def run(_args) do
    # 1. Scan project AST for library calls
    detected = scan_project_for_library_calls()

    # 2. Compare to manifest
    to_generate = filter_already_generated(detected)

    # 3. Generate missing .ex files
    generate_source_files(to_generate)

    # 4. Update manifest and lock file
    update_manifest_and_lock()

    # 5. Return :ok, normal Elixir compilation proceeds
    {:ok, []}
  end
end
```

---

## Decision 2: Cache Source Files, Not BEAM

### The Question

What should we cache to avoid regeneration?

### Options Considered

**Option A: Cache BEAM Bytecode**
- Store compiled `.beam` files
- Load directly at runtime
- Faster subsequent compilations

**Option B: Cache Source `.ex` Files**
- Store generated Elixir source
- Re-compile with normal Elixir compiler
- Portable across environments

### Decision: Option B (Cache Source)

### Rationale

BEAM bytecode has compatibility constraints:
- **OTP version**: BEAM files may not load on different OTP versions
- **Elixir version**: Some compilation changes affect bytecode
- **Compilation options**: Debug info, warnings, etc.

If we cache BEAM and restore it in CI or another developer's machine, we eventually hit "works on my machine" failures.

Caching source avoids this entirely:
- Source is portable across all environments
- Normal Elixir compilation handles bytecode generation
- Debug info, Dialyzer PLT, etc. work correctly
- No "magic" loading of pre-compiled modules

### Implementation

```
lib/snakebridge_generated/
├── numpy.ex          # Generated source (committed to git)
├── pandas.ex         # Generated source (committed to git)
└── sympy.ex          # Generated source (committed to git)

snakebridge.lock      # Environment + symbol manifest (committed to git)
```

The `_build/` directory contains compiled BEAM as usual, managed by Mix.

---

## Decision 3: Committed Source vs. Build Artifact

### The Question

Should generated adapters be committed to git or treated as ephemeral build artifacts?

### Options Considered

**Option A: Generated code in `_build/` (ignored)**
- Never committed
- CI regenerates from scratch
- Smaller git repo

**Option B: Generated code in `lib/` (committed)**
- Checked into version control
- CI uses existing code
- Deterministic builds

### Decision: Option B (Committed to Git)

### Rationale

Treating generated code as a build artifact creates problems:

1. **CI Cold Start**: Every CI run must have Python, UV, and all libraries installed to regenerate. This means you cannot deploy a "pure Elixir" release without Python available at build time.

2. **Non-Determinism**: Different CI runners might resolve different Python transitive dependencies, producing subtly different code.

3. **Slower CI**: Regeneration adds time to every build.

Committing generated source provides:
- **Deterministic builds**: Same code, every time
- **Faster CI**: No regeneration needed
- **Simpler deployment**: No Python required at build time (only at development time)
- **Code review**: Generated code changes are visible in PRs

### Git Hygiene

```gitignore
# DO NOT ignore generated code
# lib/snakebridge_generated/  <- WRONG

# DO commit these:
# - lib/snakebridge_generated/*.ex
# - snakebridge.lock
```

```
# .gitattributes - Mark as generated for better diffs
lib/snakebridge_generated/* linguist-generated=true
```

---

## Decision 4: Environment Locking (snakebridge.lock)

### The Question

How do we ensure reproducible builds when Python and its dependencies can drift?

### Options Considered

**Option A: No Locking**
- Trust that version constraints are sufficient
- Accept some non-determinism

**Option B: Version Locking**
- Lock resolved library versions
- Regenerate when versions change

**Option C: Full Environment Locking**
- Lock Python version, platform, resolved deps
- Lock generator version
- Regenerate when ANY part changes

### Decision: Option C (Full Environment Locking)

### Rationale

Version constraints alone are insufficient:

- **Python transitive dependencies**: `numpy ~> 1.26` can resolve to different transitive deps over time
- **Python version differences**: 3.10 vs 3.11 can change introspection output, doc rendering, even signatures
- **Platform differences**: Windows/macOS/Linux wheels have different features
- **Generator changes**: SnakeBridge upgrades may produce different output

The lock file captures complete environment identity:

```json
{
  "version": "3.0.0",
  "environment": {
    "snakebridge_version": "3.0.0",
    "python_version": "3.11.5",
    "python_platform": "linux-x86_64",
    "elixir_version": "1.16.0",
    "otp_version": "26.1"
  },
  "libraries": {
    "numpy": {
      "requested": "~> 1.26",
      "resolved": "1.26.4",
      "transitive_deps": {
        "packaging": "23.2"
      },
      "wheel_hash": "sha256:abc123..."
    }
  },
  "symbols": {
    "Numpy.array/1": {
      "generated_at": "2025-12-25T10:30:00Z",
      "python_signature": "array(object, dtype=None, ...)",
      "source_hash": "sha256:def456..."
    }
  }
}
```

### Invalidation Policy

When any of these change, affected bindings are regenerated:

| Change | Effect |
|--------|--------|
| SnakeBridge version | Regenerate all |
| Python version | Regenerate all |
| Library version | Regenerate that library |
| Platform | Regenerate all |
| Symbol added in code | Generate new symbol |
| Symbol removed from code | Keep (explicit prune needed) |

---

## Decision 5: Manifest Determinism (Git Merge Safety)

### The Question

How do we handle multiple developers generating different functions without causing merge conflicts?

### Scenario

```
Dev A adds Numpy.sum() → Generates entry → Commits
Dev B adds Numpy.mean() → Generates entry → Commits
Both modify snakebridge.lock → CONFLICT
```

### Decision: Deterministic, Sorted, Atomic Updates

### Implementation

1. **Sorted Keys**: Lock file and generated modules use sorted keys
2. **One File Per Library**: `lib/snakebridge_generated/numpy.ex` contains all Numpy functions, sorted alphabetically
3. **Atomic Writes**: Use temp file + rename for crash safety
4. **Merge-Friendly Format**: JSON with one entry per line for easy git merge

```json
{
  "symbols": {
    "Numpy.array/1": {"generated_at": "..."},
    "Numpy.mean/1": {"generated_at": "..."},
    "Numpy.sum/1": {"generated_at": "..."},
    "Numpy.zeros/1": {"generated_at": "..."}
  }
}
```

```elixir
# lib/snakebridge_generated/numpy.ex
# Functions in alphabetical order for stable diffs

defmodule Numpy do
  # ... module doc ...

  def array(object), do: ...
  def mean(arr), do: ...
  def sum(arr), do: ...
  def zeros(shape), do: ...
end
```

This minimizes conflicts because:
- Each developer's additions appear in predictable locations
- Sorted order means no shuffling
- One-line-per-entry JSON merges cleanly

---

## Decision 6: Dynamic Dispatch Handling

### The Question

AST scanning cannot detect `apply(Numpy, some_var, args)`. How do we handle dynamic dispatch?

### Options Considered

**Option A: Ignore Dynamic Calls**
- Document the limitation
- Developers manually generate needed functions
- Simple but incomplete

**Option B: Runtime Learning Mode**
- Record undefined calls at runtime
- Automatically add to manifest
- Scary for production stability

**Option C: Explicit Ledger Promotion**
- Record dynamic calls to a "ledger" file
- Developer explicitly promotes ledger to manifest
- Deterministic, controlled

### Decision: Option C (Explicit Ledger Promotion)

### Rationale

Automatic runtime learning undermines determinism. If different runtime paths produce different ledger contents, builds become non-reproducible.

The explicit promotion model:

1. **Development**: Runtime records dynamic calls to `snakebridge.ledger` (not committed)
2. **Developer Review**: Developer runs `mix snakebridge.promote` to see pending additions
3. **Explicit Commit**: Developer approves, ledger contents added to manifest, source regenerated
4. **Deterministic CI**: CI only uses manifest, never ledger

### Implementation

```elixir
# Runtime (dev only)
defmodule SnakeBridge.Runtime do
  def dynamic_call(module, function, args) do
    if Mix.env() == :dev do
      record_to_ledger(module, function, length(args))
    end

    # Actual call
    apply(module, function, args)
  end
end
```

```bash
# Developer workflow
$ mix snakebridge.ledger
Pending dynamic calls (not yet in manifest):
  Numpy.custom_op/3 (called 5 times in dev)
  Pandas.query/2 (called 2 times in dev)

$ mix snakebridge.promote
Adding to manifest:
  Numpy.custom_op/3
  Pandas.query/2

Generating source...
Done. Commit lib/snakebridge_generated/ and snakebridge.lock
```

---

## Decision 7: Documentation Source of Truth

### The Question

Where do docs come from: registry metadata or live Python?

### Options Considered

**Option A: Registry Metadata Authoritative**
- Pre-built doc packages on Hex
- No Python needed for docs
- May be stale

**Option B: Live Python Authoritative**
- Always query Python for docs
- Always accurate
- Requires Python available

**Option C: Hybrid with Clear Priority**
- Python is authoritative
- Registry is cache/optimization
- Explicit staleness handling

### Decision: Option C (Python Authoritative, Registry is Cache)

### Rationale

For v1, Python is the source of truth:
- Docs are always accurate to installed version
- No separate registry infrastructure needed
- Simple mental model

Registry packages become an optimization:
- Speed up cold starts
- Enable offline doc access
- Pre-computed search indexes

### Implementation

```elixir
def get_doc(module, function) do
  cond do
    # 1. Check memory cache
    cached = DocCache.get(module, function) ->
      cached

    # 2. Check registry package (if available)
    {:ok, doc} = RegistryPackage.get_doc(module, function) ->
      DocCache.put(module, function, doc)
      doc

    # 3. Fall back to live Python (authoritative)
    {:ok, doc} = PythonIntrospector.get_doc(module, function) ->
      DocCache.put(module, function, doc)
      doc

    # 4. Not found
    true ->
      nil
  end
end
```

---

## Decision 8: Security Posture (v1 Scope)

### The Question

What security guarantees does v1 provide?

### Explicit Scope for v1

**v1 DOES provide:**
- Library allowlist from mix.exs configuration
- Version pinning via lock file
- Source committed to git (auditable)
- No network access during normal compilation (after initial generation)

**v1 does NOT provide:**
- Hash-verified wheel installations (relies on UV/pip)
- Sandboxed Python execution
- Signature verification of metadata packages
- Air-gapped/offline builds (Python needed for initial generation)

### Rationale

Building a complete supply chain security system is out of scope for v1. We:
- Document what is and isn't secured
- Leverage UV's security features
- Commit generated source for auditability
- Defer advanced security to future versions

### Future Security Roadmap

**v1.1**: Wheel hash verification via UV lockfile
**v2.0**: Sandboxed Python execution option
**v2.x**: Signed metadata packages for enterprise

---

## Decision 9: Single Configuration Entrypoint

### The Question

Where do users configure SnakeBridge?

### Options Considered

**Option A: Config files (`config/config.exs`)**
- Elixir convention
- Separate from deps

**Option B: mix.exs dependency options**
- Co-located with dependency declaration
- Single source of truth

**Option C: Both (layered)**
- Mix.exs for library declaration
- Config for runtime behavior
- Potential confusion

### Decision: Option B (mix.exs Canonical, Config for Overrides)

### Rationale

Library configuration belongs with the dependency declaration:
```elixir
{:snakebridge, "~> 3.0",
 libraries: [numpy: "~> 1.26", pandas: "~> 2.0"]}
```

This is the ONLY place to declare libraries. It's clear, discoverable, and matches the mental model of "I depend on these Python libraries."

Runtime behavior (verbose logging, cache location) can optionally go in config:
```elixir
# config/dev.exs
config :snakebridge, verbose: true
```

But the default is sensible without any config.

---

## Summary Table

| Decision | Choice | Key Rationale |
|----------|--------|---------------|
| Generation approach | Pre-pass, not mid-injection | Tooling compatibility, safety |
| Cache format | Source `.ex`, not BEAM | Portability across OTP versions |
| Git status | Committed to git | Deterministic CI, faster builds |
| Environment tracking | Full lock file | Reproducibility |
| Manifest format | Sorted, atomic | Merge safety |
| Dynamic dispatch | Explicit ledger promotion | Determinism |
| Doc source of truth | Python authoritative | Accuracy |
| Security scope | Limited in v1 | Explicit, documented |
| Configuration | mix.exs canonical | Single source of truth |
