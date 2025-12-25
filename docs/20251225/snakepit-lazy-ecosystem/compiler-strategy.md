# Compiler Strategy: Deterministic Prepass

This document defines how compilation works without mid-compile injection, and how we avoid the "compiler tracer" trap.

## Decision

The canonical model is **prepass generation**. We do not pause the compiler mid-file or inject functions into loaded modules. This keeps tooling predictable and avoids race conditions.

A tracer-based approach remains an optional future experiment, but it is not required for v1.

## Prepass Lifecycle

1. **Load config** from `mix.exs` and `config/*.exs`.
2. **Create stubs** for configured libraries so modules exist early.
3. **AST scan** to identify used symbols.
4. **Generate missing adapters** into `lib/snakebridge_generated/`.
5. **Update lockfile** with environment identity.
6. **Run standard Elixir compilation**.

## Stubs

Stubs are minimal modules that provide identity and discovery hooks:

- `__snakepit_library__/0`
- `__snakepit_version__/0`
- `__functions__/0` returns cached discovery results

Stubs avoid "module not available" warnings and allow tooling to resolve module names, but they do not mask missing functions. The prepass still generates real functions before compile.

## Strict Mode

`strict: true` enforces deterministic builds:

- If adapters would need to be generated, compilation fails.
- This is the recommended CI setting.
- Developers can use `strict: false` in dev for automatic generation.

## Locking and Concurrency

Prepass generation uses file locks to avoid races:

- A global lock around `snakebridge.lock`.
- Per-library locks during adapter writes.
- Atomic file writes with temp files and rename.

## Experimental Tracer (Not Default)

A tracer is possible, but it must meet these constraints:

- Must not mutate modules mid-compilation.
- Must batch generation to avoid per-call overhead.
- Must remain compatible with parallel compilation.

If these constraints cannot be met, the tracer stays disabled.

## Failure Modes and Errors

- **Missing symbol in metadata**: compile-time warning with suggestions.
- **Dynamic call without ledger**: runtime error with guidance to use `Snakepit.dynamic_call/4`.
- **Lockfile mismatch**: compile fails with a prompt to update lockfile.

