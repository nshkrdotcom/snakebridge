# Engineering Decisions

This document captures critical design decisions, alternatives considered, and rationale. These decisions address fundamental engineering challenges that determine whether v3 works or remains a "nice dream."

---

## Decision 1: Pre-Pass Generation vs. Mid-Compilation Injection

### The Question

How do we integrate lazy generation into the Elixir compilation process?

### Options Considered

**Option A: Compiler Tracer with Mid-Compilation Injection**
- Hook into Elixir's compilation tracer
- Intercept undefined remote function calls
- Generate code and inject it "just in time"

**Option B: Pre-Pass AST Scanning with Source Generation**
- Run a separate compiler task BEFORE Elixir compilation
- Scan project source for library calls
- Generate `.ex` files to `lib/snakebridge_generated/`
- Let normal Elixir compilation proceed

### Decision: Option B (Pre-Pass Generation)

### Rationale

Mid-compilation injection has fatal flaws:

1. **Compilation Concurrency**: Mix compiles files in parallel. Injecting modules mid-flight causes race conditions.

2. **Incremental Compilation Confusion**: "I changed file A, why did module B regenerate?" becomes a recurring issue.

3. **Tooling Incompatibility**: Dialyzer, ExDoc, language servers expect code to exist as source before compilation.

4. **Hot Code Loading**: Adding functions to already-loaded modules is non-standard and complicates debugging.

Pre-pass avoids all issues:
- Dialyzer works
- ExDoc works
- IDE "go to definition" works
- Normal debugging

---

## Decision 2: Cache Source Files, Not BEAM

### The Question

What should we cache to avoid regeneration?

### Options Considered

**Option A: Cache BEAM Bytecode**
**Option B: Cache Source `.ex` Files**

### Decision: Option B (Cache Source)

### Rationale

BEAM bytecode has compatibility constraints:
- OTP version may differ
- Elixir version may differ
- Debug info settings may differ

If we cache BEAM and restore on a different machine, we eventually hit failures.

Caching source:
- Portable across all environments
- Normal Elixir compilation handles bytecode
- Debug info, Dialyzer PLT work correctly
- Generated code is human-readable

---

## Decision 3: Commit Source vs. Build Artifact

### The Question

Should generated adapters be committed to git?

### Options Considered

**Option A: In `_build/` (ignored)**
- Never committed, CI regenerates

**Option B: In `lib/` (committed)**
- Checked into git, CI uses existing

### Decision: Option B (Committed to Git)

### Rationale

Treating generated code as build artifact creates problems:

1. **CI Cold Start**: Every CI run needs Python + libraries to regenerate
2. **Non-Determinism**: Different CI runners may resolve different versions
3. **Slower CI**: Regeneration adds time

Committed source provides:
- Deterministic builds
- Faster CI
- Simpler deployment (no Python at build time)
- Code review visibility

---

## Decision 4: Full Environment Locking

### The Question

How do we ensure reproducible builds when Python can drift?

### Decision: Full Lock File

Lock everything:
- Python version
- Library versions
- Platform
- SnakeBridge version

```json
{
  "environment": {
    "snakebridge_version": "3.0.0",
    "python_version": "3.11.5",
    "python_platform": "linux-x86_64"
  },
  "libraries": {
    "numpy": {"requested": "~> 1.26", "resolved": "1.26.4"}
  }
}
```

### Invalidation Rules

| Change | Effect |
|--------|--------|
| SnakeBridge version | Regenerate all |
| Python version | Regenerate all |
| Library version | Regenerate that library |
| New symbol in code | Generate that symbol |
| Symbol removed | Keep (prune explicitly) |

---

## Decision 5: Append-Only Accumulation

### The Question

How do we handle symbols that are no longer used?

### Options Considered

**Option A: Auto-prune unused symbols**
**Option B: Manual pruning only**

### Decision: Option B (Manual Pruning)

### Rationale

Auto-cleanup creates non-deterministic builds:

```
Day 1: Use fft → generated
Day 2: Refactor, fft moves → still detected
Day 3: Different code path → fft not detected → auto-pruned
Day 4: CI fails → original code path needed fft
```

Manual pruning:
- Cache only grows
- Explicit `mix snakebridge.prune` to clean up
- Developer controls timing
- Deterministic

---

## Decision 6: Dynamic Dispatch via Ledger

### The Question

AST scanning can't detect `apply(Numpy, func, args)`. How do we handle this?

### Options Considered

**Option A: Ignore dynamic calls**
**Option B: Runtime learning mode**
**Option C: Ledger + explicit promotion**

### Decision: Option C (Ledger Promotion)

### Rationale

Automatic learning undermines determinism:

1. **Development**: Record dynamic calls to ledger (not committed)
2. **Developer Review**: `mix snakebridge.ledger` shows pending
3. **Explicit Commit**: `mix snakebridge.promote` adds to manifest
4. **Deterministic CI**: CI uses manifest only

---

## Decision 7: Python as Doc Source of Truth (Metadata Fallback Allowed)

### The Question

Where do docs come from: metadata registry or live Python?

### Options Considered

**Option A: Registry metadata authoritative**
**Option B: Live Python authoritative**
**Option C: Hybrid**

### Decision: Option B (Python Authoritative) with Optional Metadata Fallback

### Rationale

For v3, Python is the source of truth:
- Docs always accurate to installed version
- No separate registry infrastructure required
- Simple mental model for developers

Metadata fallback is allowed for CI/offline use:
- `docs.source: :metadata` avoids Python dependency
- `:hybrid` prefers metadata, falls back to Python in dev

---

## Decision 8: Security Scope (v1)

### The Question

What security guarantees does v1 provide?

### Decision: Limited, Documented Scope

**v1 DOES provide:**
- Library allowlist from mix.exs
- Version pinning via lock file
- Source committed to git (auditable)

**v1 does NOT provide:**
- Hash-verified wheel installations
- Sandboxed Python execution
- Air-gapped builds

Security is explicitly scoped and documented.

---

## Decision 9: One File Per Library

### The Question

Should we generate one file per function or one file per library?

### Decision: One File Per Library

```
✓ lib/snakebridge_generated/numpy.ex    # All functions
✗ lib/snakebridge_generated/numpy/array.ex
✗ lib/snakebridge_generated/numpy/mean.ex
```

### Rationale

- Fewer files = fewer git objects
- Sorted functions = minimal merge conflicts
- Easier to review in PRs
- Faster compilation

---

## Decision 10: Snakepit as Runtime, SnakeBridge as Codegen

### The Question

Should SnakeBridge include its own runtime or use Snakepit?

### Decision: Use Snakepit

### Rationale

Snakepit already provides:
- gRPC-based process pooling
- Session management
- Bidirectional tool bridge
- Telemetry integration
- Production-grade lifecycle management

Duplicating this in SnakeBridge would:
- Double the maintenance burden
- Create version compatibility issues
- Confuse users about which to use

Clear separation:
- **SnakeBridge**: Compile-time (scanning, introspection, generation)
- **Snakepit**: Runtime (pooling, execution, sessions)

---

## Decision 11: Strict Mode for CI

### The Question

How do we prevent unexpected generation in CI?

### Decision: `strict: true` Mode

```elixir
config :snakebridge, strict: true
```

Effects:
- **Fail** if any detected symbol not in manifest
- **Fail** if generation would be required
- **Succeed** only if generated source is complete

Use in CI to guarantee deterministic builds.

---

## Decision 12: No Timestamps in Generated Content

### The Question

Should generated files include timestamps?

### Decision: No Timestamps (Content-Addressed)

```elixir
# Good: No timestamp
# Generated by SnakeBridge v3.0.0

# Bad: Timestamp causes churn
# Generated: 2025-12-25T10:30:00Z
```

### Rationale

- Only regenerate when content changes
- Minimal git diffs
- Easier code review
- Content-addressed, not time-addressed
- Applies to generated source and manifests

---

## Decision 13: Runtime Capabilities Live in Snakepit

### The Question

Where should runtime concerns (pooling, zero-copy, crash barrier, exception translation) live?

### Decision: Snakepit Owns Runtime, SnakeBridge Emits Payloads

### Rationale

- SnakeBridge stays compile-time only (scan/introspect/generate).
- Snakepit Prime runtime owns execution, pooling, isolation, and error mapping.
- SnakeBridge only guarantees payload fields (`kwargs`, `call_type`, `idempotent`)
  and references Snakepit runtime types (`Snakepit.PyRef`, `Snakepit.ZeroCopyRef`).

---

## Decision 16: Hermetic Python Runtime

### The Question

Should we rely on system Python?

### Decision: UV-Managed Python with Hash in Lockfile

### Rationale

- Managed Python eliminates “works on my machine” drift.
- Lockfile records interpreter hash and platform identity.
- CI builds do not require system Python.

---

## Summary Table

| Decision | Choice | Key Rationale |
|----------|--------|---------------|
| Generation timing | Pre-pass | Tooling compatibility |
| Cache format | Source `.ex` | Portability |
| Git status | Committed | Determinism, faster CI |
| Environment tracking | Full lock file | Reproducibility |
| Cleanup policy | Manual prune | Determinism |
| Dynamic dispatch | Ledger + promote | Controlled |
| Doc source | Python (metadata fallback) | Accuracy + offline option |
| Security | Limited v1 scope | Explicit |
| File granularity | Per-library | Merge friendliness |
| Runtime | Snakepit | Separation of concerns |
| CI safety | Strict mode | Fail-fast |
| Timestamps | None | Content-addressed |
| Zero-copy interop | DLPack + Arrow | Performance |
| Crash barrier | Taint + rotate | Stability |
| Exception translation | Structured errors | Ergonomics |
| Hermetic runtime | UV-managed Python | Reproducibility |
