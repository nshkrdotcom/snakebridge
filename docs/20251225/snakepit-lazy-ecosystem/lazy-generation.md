# Lazy Generation Engine

This document describes how Snakepit + Snakebridge generate adapters only for the symbols your code actually uses, without mid-compilation injection.

## The Goal

Generate the smallest possible adapter surface that still preserves compile-time tooling benefits and deterministic builds.

## Primary Execution Model (Deterministic Prepass)

We do not inject functions during compilation. Instead, we run a **prepass** that generates missing adapters before Elixir compiles project sources.

Reasons:

- Tooling stays predictable (Dialyzer, ExDoc, LSP).
- No compiler tracer races.
- Deterministic diffs and reproducible builds.

## Inputs

- `libraries` list from `mix.exs`
- Introspection metadata snapshot for each library (functions, classes, docstrings, signatures)
- Project AST (Elixir source) to detect usage
- Optional runtime usage ledger for dynamic calls

## Outputs

- Stable, minimal Elixir modules under `lib/snakebridge_generated/`
- A usage ledger per library (optional)
- A lockfile with environment identity (`snakebridge.lock`)

## Prepass Stages

### 0. Stub Modules

Before scanning, we generate or refresh small stubs for each configured library so modules exist for tooling and name resolution. Stubs do not provide function bodies.

### 1. AST Scan

During `mix compile`, a prepass scans project files to find call sites:

- `Sympy.sqrt(x)`
- `Sympy.Matrix(...)`
- `Sympy.JSONDecodeError.message()`

The scanner resolves module aliases and imports so it can map calls to configured libraries.

### 2. Symbol Resolution

For each detected call, the scanner resolves the symbol from the metadata snapshot:

- If the symbol exists, it is queued for generation.
- If missing, it is recorded for diagnostics.

### 3. Incremental Generation

The generator merges new symbols with the existing adapter set and writes missing modules. Symbols are appended, never removed, unless explicitly pruned.

### 4. Lockfile Update

A deterministic `snakebridge.lock` captures environment identity and the resolved dependency set so generation is reproducible in CI.

### 5. Compile

Elixir compiles against real source files, so undefined function warnings do not appear.

## Dynamic Dispatch (The Blindspot)

AST scanning cannot see calls like `apply(module, fun, args)`.

We handle this explicitly:

- Use `Snakepit.dynamic_call/4` for runtime-dispatched calls.
- Dynamic calls are recorded in a **ledger** in dev.
- A developer promotes the ledger to the manifest with `mix snakepit.promote_ledger`.

This avoids silent, nondeterministic growth in CI while preserving developer ergonomics.

## Determinism and Locking

Generation is guarded by a lockfile and file locks:

- **Lockfile** includes Python version, platform, resolved dependencies, and generator hash.
- **File locks** prevent concurrent compiles from corrupting manifests.
- **Stable file naming** and **sorted manifest output** avoid merge conflicts.

See `determinism-lockfile.md` for details.

## Build Flow

```
Prepass
  -> Write stubs
  -> AST scan
  -> Resolve symbols via metadata
  -> Generate missing adapters
  -> Update lockfile

Compile
  -> Normal Elixir compilation
```

## Why This Works

- The adapter surface is always as small as possible.
- The surface only grows when the project grows.
- Build times stay proportional to actual usage.
- Tooling behaves like standard Elixir because source exists before compile.

