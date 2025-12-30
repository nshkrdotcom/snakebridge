# SnakeBridge Universal FFI - Master Implementation Plan

## Executive Summary

This document provides a comprehensive plan to transform SnakeBridge from a "compile-time adapter generator" into a true **Universal FFI** where "most any Python library just works."

Based on three critical review documents (001_gpt52.md, 002_g3p.md, 003_g3p.md), we have identified **8 implementation domains** with 25+ critical issues to address.

## Domain Overview

| Domain | Priority | Description | Key Files |
|--------|----------|-------------|-----------|
| **1. Type System & Marshalling** | P0 | Fix atom encoding, auto-ref fallback, boundary marshalling | types.ex, snakebridge_types.py |
| **2. Signature & Arity Model** | P0 | Fix manifest/arity mismatch, C-extension signatures, keyword-only params | manifest.ex, generator.ex, introspector.ex |
| **3. Class & Module Resolution** | P0 | Auto-disambiguate class vs submodule, module attributes, name sanitization | generator.ex, compile/snakebridge.ex |
| **4. Dynamic Dispatch & Proxy** | P1 | Ghost module for un-generated methods, no-codegen escape hatch | runtime.ex, dynamic.ex (new) |
| **5. Reference Lifecycle** | P0 | Auto-ref unknown types, process-monitor cleanup, session isolation | ref.ex, snakebridge_adapter.py |
| **6. Python Idioms Bridge** | P0 | Generators/iterators, context managers, Elixir callbacks | runtime.ex, stream_ref.ex (new) |
| **7. Protocol Integration** | P1 | Dunder mapping (Inspect, Enumerable, String.Chars), exception hierarchy | ref.ex, error_translator.ex |
| **8. Cleanup & Tech Debt** | P1 | Consolidate introspection, fix telemetry, wire registry, thread safety | introspector.ex, telemetry.ex |

## Critical Path

```
Phase 1: Foundations (Domains 1-3, 5) - BLOCKING
  ├── Domain 1: Type System fixes (atoms → strings, auto-ref)
  ├── Domain 2: Arity model fix (range matching)
  ├── Domain 3: Class/submodule disambiguation
  └── Domain 5: Reference lifecycle (process monitors)

Phase 2: Core Features (Domains 4, 6)
  ├── Domain 4: Dynamic dispatch
  └── Domain 6: Python idioms (generators, context managers)

Phase 3: Polish (Domains 7-8)
  ├── Domain 7: Protocol integration
  └── Domain 8: Tech debt cleanup
```

## P0 Issues Summary (Must-Have for MVP)

### From Domain 1: Type System
1. **Atom decoding** - Python `Atom()` objects break libraries; must default to strings
2. **String fallacy fix** - `str(value)` fallback must become auto-ref creation
3. **Boundary marshalling** - Runtime.call must auto-encode/decode

### From Domain 2: Signature Model
4. **Arity mismatch** - Manifest stores required_arity but scanner reports call-site_arity
5. **C-extension signatures** - `parameters: []` must generate variadic wrappers
6. **Keyword-only validation** - Required keyword-only params must be detected/enforced

### From Domain 3: Class Resolution
7. **Class vs submodule** - `Lib.Foo.bar` must auto-detect if Foo is class or submodule
8. **Module attributes** - Must access `math.pi`, `numpy.nan`, etc.

### From Domain 5: Reference Lifecycle
9. **Auto-ref fallback** - Unknown types must return refs, not strings
10. **Process monitors** - Replace TTL-based pruning with ownership tracking

### From Domain 6: Python Idioms
11. **Generators** - Must detect and wrap as Elixir Enumerable, not serialize
12. **Context managers** - Must support `__enter__`/`__exit__` with guaranteed cleanup

## Files to Create

| File | Domain | Purpose |
|------|--------|---------|
| `lib/snakebridge/dynamic.ex` | 4 | Dynamic dispatch for un-generated methods |
| `lib/snakebridge/stream_ref.ex` | 6 | Generator/iterator Enumerable wrapper |
| `lib/snakebridge/session_manager.ex` | 5 | Process-monitor lifecycle |
| `lib/snakebridge/callback_registry.ex` | 6 | Elixir callback passing to Python |
| `lib/snakebridge/with_context.ex` | 6 | Context manager macro |
| `lib/snakebridge/protocol_impl.ex` | 7 | Protocol implementations for Ref |
| `lib/snakebridge/dynamic_exception.ex` | 7 | Dynamic exception creation |
| `priv/python/session_manager.py` | 5 | Session-scoped registries |

## Files to Modify

| File | Domains | Key Changes |
|------|---------|-------------|
| `lib/snakebridge/types/encoder.ex` | 1, 6 | Auto-ref, callback encoding |
| `lib/snakebridge/types/decoder.ex` | 1, 5, 6 | Ref decoding, stream_ref |
| `priv/python/snakebridge_types.py` | 1, 5 | Auto-ref fallback, atom→string |
| `priv/python/snakebridge_adapter.py` | 5, 6, 7, 8 | Thread safety, dunder calls |
| `lib/snakebridge/manifest.ex` | 2, 3 | Arity range, class metadata |
| `lib/snakebridge/generator.ex` | 2, 3 | Variadic wrappers, name sanitization |
| `lib/snakebridge/runtime.ex` | 1, 4, 6, 7 | Auto-encode, dunder calls, stream_next |
| `lib/snakebridge/introspector.ex` | 7, 8 | Dunder detection, consolidation |
| `lib/snakebridge/ref.ex` | 7 | Protocol implementations |
| `lib/snakebridge/error_translator.ex` | 7 | Dynamic exceptions |

## Implementation Prompts

Each domain has an associated implementation prompt in `docs/20251229/prompts/`:

- `prompt_01_type_system.md`
- `prompt_02_signature_model.md`
- `prompt_03_class_resolution.md`
- `prompt_04_dynamic_dispatch.md`
- `prompt_05_reference_lifecycle.md`
- `prompt_06_python_idioms.md`
- `prompt_07_protocol_integration.md`
- `prompt_08_tech_debt.md`

## Testing Strategy

Each prompt includes TDD requirements:
1. Write tests first based on acceptance criteria
2. Run tests (expect failures)
3. Implement feature
4. Run tests (expect pass)
5. Run full suite (`mix test`, `mix dialyzer`, `mix credo`)
6. Update examples in `examples/` directory

## Success Criteria

- All existing tests pass
- New tests for each domain pass
- Examples in `examples/run_all.sh` pass
- No dialyzer errors
- No credo warnings
- README updated with new features
- All prompts can be executed in sequence
