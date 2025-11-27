# Phase 1 Critical Review

## Executive Summary
The roadmap assumes a mature, flexible core, but the current code remains a thin wrapper around `Snakepit` with limited type awareness and minimal error handling. Many advertised features (type-safe specs, streaming patterns, generalized adapters) are not implemented in `lib/snakebridge/*` or the Python adapter, so stacking larger abstractions on top risks building on sand. Given this is greenfield (no legacy users) and timeline/resources are not the constraint, the right move is “fundamentals first”: correctness, error handling, streaming, and one solid data/ML adapter to serve the ML control-plane goals (e.g., unsloth) before broad generalization.

Biggest concerns: (1) Over-engineering via registries/strategy chains before fixing correctness, error handling, and real Snakepit integration; (2) Optimistic claims about “works for any Python library” given current introspection/type gaps; (3) Arrow/Nx/Explorer is premature for single-node v1—defer heavy data-plane work but keep a documented path for the future distributed Snakepit+Arrow rebuild (targeting Spring 2026).

## Feasibility Analysis
### Type Mapper Chain
- Current mapper is ~130 LOC of simple pattern matching with no integration into generation (see `lib/snakebridge/type_system/mapper.ex:9-87`), and generator emits only `map()` types (`lib/snakebridge/generator.ex:153-221`). Introducing a chain/registry adds indirection before basic coverage (e.g., tuples, kwargs, default values) or usage in codegen exists. A simpler win is to hardcode the 10-15 common shapes and actually emit specs from descriptors; pluggability can wait until real custom types appear. Hidden costs: ordering/priority bugs, config surface growth, and test matrix explosion.
### Adapter Registry
- Today the catalog is a static list of four entries (`lib/snakebridge/catalog.ex:24-138`). A dynamic registry is extra plumbing without a discovery story (who registers? when? per app or per dep?) or lifecycle guarantees. Simpler: accept adapters via config (env or application config) and load modules dynamically. Maintenance burden: registry persistence, conflict resolution, and API stability across versions.
### Generator Strategy
- Duplication exists, but generator is small and single-target (Elixir). A full strategy pattern for multi-language/code-targets is premature; focus on extracting helpers to remove duplicated method/function generation and add type-aware specs/guards. Over-abstraction risks slowing iteration without user-facing benefit.
### Execution Plans
- Runtime is ~150 LOC and already readable (`lib/snakebridge/runtime.ex`). Adding declarative plans before timeouts, retries, telemetry, and error classification exist adds ceremony without solving real pain. Start with small, composable helpers (e.g., a shared `execute_call/1` that handles timeouts/result decoding) before a full plan DSL.
### Python Handler Chain
- The Python adapter is ~250 LOC and already linear. A handler chain is reasonable for specialization, but duplication is not the bottleneck; correctness is (no cleanup, no depth recursion, no type coercion). A lean mixin/composition approach or reusable helper functions would achieve 80% benefit with less ordering/dispatch complexity. Also, specialized adapters currently instantiate a fresh generic adapter each call (`priv/python/adapters/genai/adapter.py`), so fixing that concrete inefficiency is higher value than designing a chain.
### Arrow Integration
- Arrow IPC over gRPC is not zero-copy; it’s just a different payload. Adding `pyarrow`, Nx, and Explorer introduces heavy deps, native binaries, and GPU/CPU memory considerations. The claimed 20-100x speedup applies to in-process columnar sharing, not serialized hops. Prove the need with benchmarks on current JSON/protobuf paths and a single NumPy array pipeline before committing. Otherwise risk build/install friction and larger wheels for all users.

## Gap Analysis
- No real Snakepit integration tests; `Runtime.execute_stream/5` bypasses the adapter abstraction entirely (`lib/snakebridge/runtime.ex:42-44`), and there’s no error propagation/telemetry/timeout story.
- Introspection is shallow: `describe_library` doesn’t traverse submodules, ignores type hints/defaults, and treats `discovery_depth` only as a method-depth limit (`priv/python/snakebridge_adapter/adapter.py`). This undermines “works with any library” claims.
- Generator ignores type descriptors, async, kwargs, defaults, and streaming flags—producing `map()` specs that Dialyzer can’t help with.
- No migration plan for existing configs when registries/strategies land; breaking changes to config shape aren’t addressed.
- Security, resource limits, and isolation aren’t planned beyond a test file list; no threat model or sandboxing guidance.
- Operational concerns absent: version pinning for heavy deps (torch/transformers), GPU availability, Python env bootstrap for CI, caching/TTL for Python instances, or cleanup semantics.
- Documentation debt persists (status/readme versions disagree; STATUS.md is outdated vs mix version), risking misaligned expectations.

## Assumption Challenges
- “Generic adapter works with ANY Python library”: Current introspection fails on dynamic attributes, C-extensions without inspectable signatures, metaclasses, or modules requiring side-effectful imports. No handling of async generators or descriptors; instance storage lacks TTL. This is optimistic.
- “Arrow provides 20-100x speedup”: Only in shared-memory columnar contexts. Across gRPC you copy into IPC buffers and back into BEAM terms; expect marginal gains unless batch sizes are huge and conversion dominates.
- “Type Mapper Chain is highest impact”: The mapper isn’t used in generation today; adding 10 concrete mappings (tuple, bytes/bitstring, datetime, numpy ndarray as list) plus emitting specs would deliver immediate value.
- “14 weeks is realistic”: Phases 2-3 include heavy GPU/ML stacks (Unsloth, Transformers, DSPy) plus Arrow/Nx/Explorer plus generalized streaming—easily quarters of work for 2-3 engineers given install/CI headaches.
- “Streaming infra already solid”: No Elixir-side stream wrappers, backpressure, or cleanup; Python adapter doesn’t support async generators or flow control.

## Priority Recommendations
- Fundamentals-first scope (agree): real Snakepit round-trips, error typing, timeouts, and telemetry in `SnakeBridge.Runtime` and Python adapter.
- Add minimal, type-aware generation (use descriptors to emit specs/guards) and expand mapper to top real-world types before pluggable chains.
- Build one high-demand adapter aligned to ML control-plane needs (NumPy/pandas as data foundation, then unsloth as the first ML target) end-to-end with benchmarks; LLMs are handled elsewhere.
- Postpone Arrow/Nx/Explorer to a spike with benchmarks; keep default JSON/protobuf path. Document the path to “distributed Snakepit + Arrow” for later (Spring 2026) while keeping single-node v1 lightweight.
- Keep registries/strategy patterns out of Phase 1; refactor duplication with small helpers instead.

## Testing Strategy Critique
- Proposed TDD suites assume features that don’t exist (streaming detection, Arrow IPC). There’s no plan for Python-side unit tests, fixture generation, or CI matrix across Python versions/OSes. GPU tests (Unsloth/Transformers) are unaddressed for gating/skip logic.
- Mocks are static and cannot simulate errors/latency (`test/support/snakepit_mock.ex`); no property/golden tests to ensure generated modules stay stable.
- No contract tests between Elixir and Python to pin protocol payloads or error shapes; this is needed before refactors.

## Cross-Ecosystem Critique
- PyO3/JPype lessons rely on compile-time traits/macros and shared memory; SnakeBridge rides gRPC/ports, so zero-copy and trait-style ergonomics won’t translate directly. Borrowed lifetimes and pointer ownership analogies are inapplicable.
- Arrow “zero-copy” lessons from reticulate/Julia assume in-process; here it’s serialization. Overstating applicability risks wasted effort.
- Missing comparison to simpler patterns (e.g., http+json bridges like FastAPI clients) that might suit many users without heavy infra.

## Practical Concerns
- Backward compatibility: registry/type-mapper config changes could break existing configs; no migration plan.
- Dependency bloat: adding Nx/Explorer/pyarrow/torch/transformers balloons install size and build times for users who just need JSON/requests.
- Operational risk: no cleanup of Python instances in adapter; memory leaks across long-lived sessions are likely.
- Documentation drift: README advertises features not present in code (bidirectional tools, incremental caching), eroding trust.

## Alternative Approaches
- Type mapper: add a small table of common types and emit specs from descriptors; delay chain/behaviour until real custom type demand surfaces.
- Adapter registry: allow `config :snakebridge, adapters: [MyAdapter]` or a simple module lookup; avoid global registry plumbing.
- Generator: factor shared helpers for module naming/docstrings/session handling; add typespec generation using mapper; skip full strategy pattern.
- Execution: introduce a thin `execute_call/2` with timeout/error decoding; add telemetry; revisit declarative plans later.
- Python handlers: extract shared helpers/mixins; avoid chains until multiple specializations collide.
- Arrow: prototype behind a feature flag for a single NumPy path; measure vs JSON before committing; document the future distributed Snakepit+Arrow path for Spring 2026.

## Recommended Changes
- Phase 1 = fundamentals: real Snakepit integration tests (non-mock), error/timeout handling, minimal streaming wrapper on Elixir side, mapper+generator type emission, and one focused adapter (NumPy/pandas) plus the first ML target (unsloth) with benchmarks. LLMs can stay out of scope here.
- Update documentation/status to match reality and set expectations; mark unimplemented features.
- Define a compat policy for config changes before introducing registries/behaviours (even if greenfield, future you will need it).
- Add protocol/golden tests for `describe_library` and `call_python` payloads to guard refactors.
- Plan an Arrow spike with benchmarks and rollback plan; keep default path JSON/protobuf for single-node v1 while documenting the future distributed Snakepit+Arrow direction (Spring 2026).

## Questions for the Team
- Confirm single-node v1 constraints and any early requirements that would force design hooks for the future distributed Snakepit+Arrow rebuild.
- Clarify opt-in strategy for heavy deps (Nx/Explorer/pyarrow/torch) so the core stays light while supporting ML control-plane needs.
- What are the minimum ML control-plane scenarios to validate first (e.g., unsloth training/inference, experiment tracking hooks), and how will success be measured?
