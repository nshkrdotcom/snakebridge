# Towards a Universal Python Adapter for SnakeBridge

## 1. Context
- **Snakepit** guarantees high-performance, session-aware process pools and streaming channels to Python runtimes.
- **SnakeBridge** layers configuration + metaprogramming on top of Snakepit to auto-generate Elixir wrappers for arbitrary Python libraries (`Config` + `Discovery` + `Generator`).
- Synapse (and other BEAM agent frameworks) want a *single* abstraction so they never write bespoke glue per Python package.

Question: *Can we deliver a pure, uniform interface that works for any Python library without hand-edits, even across async/streaming/stateful behaviors?*

## 2. Sources of Leaky Abstractions Today
1. **Execution shapes vary wildly**
   - Stateless functions (e.g., `json.dumps`) vs. long-lived objects (`langchain.ChatPromptTemplate`) vs. background workers (`autogen` delegates) all expose different lifecycles.
2. **Type surfaces are incomplete**
   - Python type hints are often missing or `Any`, docstrings drift from reality, and runtime polymorphism breaks static inference.
3. **Async and streaming semantics**
   - Some APIs return awaitables, some yield generators, some push callbacks/events, others rely on websockets. SnakeBridge currently models just sync + simple streaming.
4. **Side-channel dependencies**
   - Environment variables, file descriptors, GPU handles, open sockets, global singletons (e.g., `dspy.settings.configure`) leak into user code unless we model them explicitly.
5. **Domain-specific protocols**
   - Tool registries, LangGraph edges, AutoGen planning loops, RLHF trainers all encode contracts that cannot be inferred only from function signatures.

## 3. Assessment: Can We Have a "Pure" Interface?
- **In theory**: If every Python library published a fully-typed behavioral schema (methods + effects + concurrency contracts), SnakeBridge could generate perfect wrappers.
- **In practice**: We can cover ~80% automatically, but the last mile (complex workflows, custom control-flow, bespoke streaming formats) still needs targeted descriptors or extension hooks.
- **Metaprogramming limits**: Code generation can map signatures, but it cannot invent semantics like "this coroutine never resolves until you call `finish()`". We must expose configuration hooks where humans declare the contract once, after which everything downstream stays uniform.

## 4. Proposed Universal Adapter Architecture
### 4.1 Layered Contract Model
| Layer | Responsibility | Notes |
| --- | --- | --- |
| **Core Execution Protocol (Snakepit)** | Process pooling, session affinity, request/stream envelopes, telemetry hooks | Already production-ready |
| **Capability Schema (SnakeBridge Config++)** | Declarative description of objects/functions, their execution mode, streaming behavior, lifecycle, bidirectional tooling | Needs extension to capture async, events, env preconditions |
| **Behaviour Profiles** | Reusable mixins defining semantics (e.g., `:pure_function`, `:stateful_worker`, `:generator_stream`, `:background_job`) | Each profile maps to runtime scaffolding + type defaults |
| **Customization Hooks** | Optional modules for transformation, validation, fallback logic | Keeps escape hatches without editing generated code |

### 4.2 Capability Extensions
1. **Execution Modes** (`:sync`, `:async`, `:generator`, `:task_stream`, `:event_channel`)
2. **Lifecycle Contracts** (`create`, `configure`, `heartbeat`, `cleanup`, `checkpoint`)
3. **State Channels**: differentiate between *session state* (Snakepit worker), *instance state* (Python object), and *global state* (module-level singletons).
4. **I/O Contracts**: declarative mapping of payload schemas, telemetry names, and backpressure/timeout policies.
5. **Bidirectional Tooling**: first-class config for Python→Elixir callbacks (already present but expand to async + streaming contexts).

### 4.3 Async & Streaming Handling
- Standardize on gRPC bi-directional streams for **all** non-blocking flows.
- Introduce a `SnakeBridge.Stream.Adapter` behavior that can wrap Python async generators, background tasks, and callback emitters into the common stream channel.
- Provide default adapters:
  1. `AwaitableAdapter` – resolves asyncio futures and returns result.
  2. `GeneratorAdapter` – iterates Python generators and emits chunk envelopes.
  3. `CallbackAdapter` – monkeypatches/exposes Python callback registration and forwards events to Elixir.
  4. `TaskChannelAdapter` – for long-running jobs producing status + final result.

### 4.4 Schema + Discovery Enhancements
- **Discovery**: run lightweight test invocations (in sandbox) to observe runtime types, streaming patterns, and metadata (beyond static signature inspection).
- **Schema**: extend `SnakeBridge.Config` with fields like `execution_mode`, `stream_payload`, `state_scope`, `preconditions`, `postprocessors`.
- **Diff-aware caching**: store observed behaviors alongside introspection to avoid rerunning expensive probes unless the Python package version changes.

### 4.5 Customization Pipeline
1. **Declarative first**: everything expressible via config (profiles, mixins, macros).
2. **Hook modules** for bespoke logic, e.g., `result_transform`, `error_adapter`, `async_wrapper`.
3. **Fallback**: allow embedding raw Elixir code blocks for the few cases where automation cannot capture semantics; still keep them co-located with config so they benefit from the same build pipeline.

## 5. Implementation Roadmap
1. **Schema v2**
   - Add capability fields described above
   - Provide migration tooling for existing configs
2. **Profile Library**
   - Ship built-in profiles for common interaction models (stateless function, stateful object, streaming generator, langgraph node, tool registry, evaluation harness)
3. **Stream/Async Adapters**
   - Implement adapter behaviors + default modules bridging asyncio/generators/callbacks to Snakepit streams
4. **Enhanced Discovery**
   - Allow discovery to execute sample calls (with sandboxed inputs) to infer whether a method returns `Awaitable`, yields generators, or requires callbacks
5. **Developer Tooling**
   - VSCode/LSP hints for new config fields
   - Mix tasks to lint capability completeness and simulate runtime bridging
6. **Canonical Adapter Catalog**
   - Ship curated configs (LangChain, LangGraph, DSPy, AutoGen, LlamaIndex, SentenceTransformers, LangSmith evaluators) maintained in-repo, exercising the full schema

## 6. Risks & Mitigations
| Risk | Impact | Mitigation |
| --- | --- | --- |
| Python libraries without type info | Generated specs degrade | Allow manual overrides + runtime inference | 
| Highly dynamic behavior (metaclasses, runtime code gen) | Hard to introspect | Require user-supplied hook modules or limit to supported patterns |
| Async context mismatch (asyncio vs threads) | Deadlocks / leaks | Standardize adapters that manage event loops per worker; document constraints |
| Performance overhead from reflection | Slower generation | Cache discovery artifacts and reuse across builds |

## 7. Conclusion
- A truly "pure" universal adapter is unattainable because semantics cannot be inferred perfectly.
- However, by elevating the configuration schema to capture execution modes, lifecycle, and async semantics, plus providing reusable behavior profiles, SnakeBridge can cover the vast majority of Python libraries without bespoke Elixir code.
- The remaining gaps become explicit hook points rather than ad-hoc patches, keeping Synapse (and other consumers) in a declarative, maintainable workflow.

## 8. Next Steps
1. Finalize Schema v2 proposal + RFC.
2. Prototype stream adapters against a complex library (LangGraph or AutoGen) to validate capability coverage.
3. Backfill curated configs into the repository and wire CI tests using the real Python adapters.
