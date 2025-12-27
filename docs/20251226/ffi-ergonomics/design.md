# SnakeBridge FFI Ergonomics and Helper Registry

Date: 2025-12-26
Status: Draft
Owner: SnakeBridge core

## Summary

SnakeBridge generates Elixir wrappers for Python libraries. Most calls map
cleanly, but some Python APIs require non-serializable objects or implicit
runtime configuration (ex: SymPy implicit multiplication). This document
proposes an ergonomic layer that preserves a strict data boundary while
minimizing one-off glue code.

## Background

- The bridge can only pass serializable data across the wire.
- Many Python APIs expect live objects or configuration objects.
- Current workaround is a project-local Python helper module.

## Goals

- Reduce custom Python glue for common library patterns.
- Keep the call boundary explicit and debuggable.
- Provide safe defaults that do not enable arbitrary execution by default.
- Preserve compatibility with current runtime contract.

## Non-goals

- Transpiling Elixir into Python.
- Arbitrary Python execution enabled by default.
- Full mirror of Python object semantics in Elixir.

## Proposed Design

### 1) Helper Discovery and Registry

Introduce a helper registry in the Python adapter:

- Helpers are named callables stored in a Python dictionary.
- Helpers can be loaded from:
  - `priv/python/helpers/*.py` (project local)
  - `priv/python/helpers/*.py` (SnakeBridge helper pack)
  - additional `helper_paths` in config

The adapter exposes a registry index and a call path:

```
helpers = {
  "sympy.parse_implicit": parse_expr_implicit,
  "numpy.asarray_safe": asarray_safe,
}
```

Elixir can invoke helpers by name:

```
SnakeBridge.Runtime.call_helper("sympy.parse_implicit", ["2x"], %{})
```

### 2) Generated Helper Wrappers

SnakeBridge uses the helper registry to generate Elixir wrappers under
`lib/snakebridge_generated/helpers/`:

```
# Auto-generated
Sympy.Helpers.parse_implicit("2x")
```

This keeps user code clean and consistent while still using explicit calls.

### 3) Handle-Based Object Model (Explicit)

For stateful Python objects, use explicit references:

- `call_class` returns a `Snakepit.PyRef`
- `call_method` operates on the ref
- `release` deletes the ref on the Python side

Lifecycle:

- Refs are scoped to a session and cleaned on session end.
- Optional explicit release for long-lived sessions.

### 4) Optional Inline Python (Advanced, Off by Default)

Provide an opt-in inline execution for advanced cases:

```
SnakeBridge.Runtime.exec("""
from sympy.parsing.sympy_parser import parse_expr, standard_transformations
from sympy.parsing.sympy_parser import implicit_multiplication_application
return parse_expr(expr, transformations=standard_transformations + (implicit_multiplication_application,))
""", %{"expr" => "2x"})
```

- Guarded by `inline_enabled: true` config.
- Only allowed in trusted environments.
- Returns serializable output or a ref.

### 5) Error Mapping and Suggestions

Enhance error classification:

- Missing helper name -> clear suggestion to install helper pack or add helper.
- Non-serializable arg -> suggestion to use helper or refs.
- Registry mismatch -> suggestion to run `mix snakebridge.setup` or reload.

## Example: SymPy Implicit Multiplication

Without helpers, the API needs a Python-side transformation object. With
registry helpers:

```
Sympy.Helpers.parse_implicit("2x")
```

This keeps the complexity in Python and the call boundary explicit.

## Configuration

Proposed keys:

```
config :snakebridge,
  helper_paths: ["priv/python/helpers"],
  helper_pack_enabled: true,
  helper_allowlist: :all,
  inline_enabled: false
```

## Compatibility

- Helper registry is additive; existing wrappers remain unchanged.
- Inline execution is off by default.
- No changes required to Snakepit runtime contract.

## Testing Plan

- Unit tests for helper discovery and registry loading.
- Integration tests for helper invocation.
- Error classification tests for missing helper or bad args.

## Rollout Plan

1. Implement helper registry and discovery.
2. Generate helper wrappers during compile.
3. Add error suggestions and doc updates.
4. Add optional inline execution behind config flag.

## Open Questions

- How to version and update helper packs safely?
- Should helper registry be mutable at runtime?
- Do we allow project helpers to shadow pack helpers?
