# Implementation Roadmap

## Overview

This roadmap outlines the phased development of AutoBridge, from core infrastructure through production readiness.

---

## Phase 0: Foundation (4-6 weeks)

### Goals
- Extend SnakeBridge with AutoBridge module structure
- Implement basic adapter registry
- Set up observation infrastructure

### Deliverables

#### 0.1 Module Structure
```
lib/autobridge/
├── autobridge.ex              # Main API
├── adapter_registry.ex        # Adapter storage/lookup
├── observer.ex                # Call observation
├── config.ex                  # Configuration
└── types.ex                   # Type definitions
```

#### 0.2 Basic Registry
```elixir
defmodule AutoBridge.AdapterRegistry do
  def register(library, config)
  def lookup(library)
  def list_all()
  def update(library, updates)
end
```

#### 0.3 Observation System
```elixir
defmodule AutoBridge.Observer do
  def observe(library, function, args, result)
  def get_observations(library)
  def clear(library)
end
```

### Verification
- Unit tests for registry CRUD
- Integration test: observe calls, retrieve observations

---

## Phase 1: Discovery Agent (3-4 weeks)

### Goals
- Automatic Python library introspection
- Library classification heuristics
- Initial config generation

### Deliverables

#### 1.1 Enhanced Discovery
```elixir
defmodule AutoBridge.Agents.Discovery do
  def discover(library_name)
  def introspect(library_name)
  def classify(schema)
  def generate_config(schema, classification)
end
```

#### 1.2 Classification System
```elixir
@archetypes [
  :math_symbolic,    # SymPy-like
  :text_processing,  # pylatexenc-like
  :data_processing,  # pandas-like
  :ml_framework,     # torch-like
  :generic           # fallback
]
```

#### 1.3 Config Templates
```
priv/autobridge/templates/
├── math_symbolic.exs
├── text_processing.exs
└── generic.exs
```

### Verification
- Discover SymPy → generates valid config
- Discover pylatexenc → correct classification
- Generated configs compile without error

---

## Phase 2: Learning System (4-5 weeks)

### Goals
- Pattern detection from observations
- Confidence scoring
- Basic refinement proposals

### Deliverables

#### 2.1 Pattern Detector
```elixir
defmodule AutoBridge.Agents.Observer.PatternDetector do
  def detect_type_patterns(observations)
  def detect_argument_patterns(observations)
  def detect_error_patterns(observations)
end
```

#### 2.2 Confidence Scoring
```elixir
defmodule AutoBridge.Confidence do
  def calculate(library)
  def breakdown(library)
  # Returns: 0.0 - 1.0
end
```

#### 2.3 Refinement Proposals
```elixir
defmodule AutoBridge.Agents.Refiner do
  def propose(:typespec, patterns)
  def propose(:default, patterns)
  def propose(:docstring, patterns)
end
```

### Verification
- 50 observations → patterns detected
- Confidence increases with observations
- Refinement proposals are valid Elixir

---

## Phase 3: Interactive DevShell (3-4 weeks)

### Goals
- IEx integration
- Real-time refinement UI
- Accept/reject workflow

### Deliverables

#### 3.1 DevShell Module
```elixir
defmodule AutoBridge.DevShell do
  def install()
  def display_proposal(proposal)
  def handle_input(input)
end
```

#### 3.2 Status Display
```elixir
def status(library)
def pending(library)
def review(library, refinement_id)
```

#### 3.3 Actions
```elixir
def accept(refinement_id)
def reject(refinement_id)
def modify(refinement_id, changes)
def accept_all(library, opts)
```

### Verification
- DevShell installs in IEx
- Proposals display correctly
- Accept/reject modifies config

---

## Phase 4: LLM Integration (3-4 weeks)

### Goals
- LLM backend abstraction
- Smart classification with fallback
- Intelligent refinement generation

### Deliverables

#### 4.1 LLM Backend
```elixir
defmodule AutoBridge.LLMBackend do
  @callback complete(prompt, opts) :: {:ok, String.t()}
end

defmodule AutoBridge.LLMBackend.Ollama do
  @behaviour AutoBridge.LLMBackend
end

defmodule AutoBridge.LLMBackend.OpenAI do
  @behaviour AutoBridge.LLMBackend
end
```

#### 4.2 AI-Enhanced Discovery
```elixir
def classify_with_llm(schema)
def generate_refinements_with_llm(patterns)
```

### Verification
- Ollama backend: local model responds
- OpenAI backend: API integration works
- LLM-generated configs are valid

---

## Phase 5: Finalization & Production (4-5 weeks)

### Goals
- Finalization workflow
- Test generation
- Optimized compilation

### Deliverables

#### 5.1 Finalization
```elixir
defmodule AutoBridge.Lifecycle do
  def finalize(library)
  def validate(library)
  def freeze(library)
end
```

#### 5.2 Test Generation
```elixir
defmodule AutoBridge.TestGenerator do
  def generate_from_observations(library)
  def run_test_suite(library)
end
```

#### 5.3 Production Module
```elixir
defmodule AutoBridge.Compiler do
  def compile_frozen(library)
  def optimize(module)
end
```

### Verification
- Finalization produces frozen config
- Generated tests pass
- Compiled module works in production

---

## Phase 6: Priority Libraries (6-8 weeks)

### Goals
- Complete integration for SymPy, pylatexenc, Math-Verify
- Bundled adapters
- Documentation

### Deliverables

#### 6.1 SymPy Adapter
```
priv/autobridge/bundled/sympy.exs
lib/autobridge/bundled/sympy.ex
test/autobridge/sympy_test.exs
```

#### 6.2 pylatexenc Adapter
```
priv/autobridge/bundled/pylatexenc.exs
lib/autobridge/bundled/pylatexenc.ex
```

#### 6.3 Math-Verify Adapter
```
priv/autobridge/bundled/math_verify.exs
lib/autobridge/bundled/math_verify.ex
```

### Verification
- All three libraries work end-to-end
- Pipeline example from priority-libraries.md works
- Benchmarks: < 5% overhead

---

## Phase 7: Maintenance Agent (3-4 weeks)

### Goals
- Version monitoring
- API change detection
- Update proposals

### Deliverables

#### 7.1 Maintainer Agent
```elixir
defmodule AutoBridge.Agents.Maintainer do
  def check_versions()
  def detect_changes(library)
  def propose_updates(library, changes)
end
```

### Verification
- Detects version changes
- Identifies breaking changes
- Proposes valid updates

---

## Timeline Summary

```
Phase 0: Foundation          [Week 1-6]      ████████████
Phase 1: Discovery Agent     [Week 7-10]         ████████
Phase 2: Learning System     [Week 11-15]            ██████████
Phase 3: Interactive Dev     [Week 16-19]                ████████
Phase 4: LLM Integration     [Week 20-23]                    ████████
Phase 5: Finalization        [Week 24-28]                        ██████████
Phase 6: Priority Libraries  [Week 29-36]                            ████████████████
Phase 7: Maintenance         [Week 37-40]                                    ████████

Total: ~40 weeks to production-ready with bundled adapters
```

---

## Milestones

| Milestone | Target | Criteria |
|-----------|--------|----------|
| **M1: Observable** | Week 6 | Can observe function calls, store in registry |
| **M2: Discoverable** | Week 10 | Can auto-discover and classify libraries |
| **M3: Learnable** | Week 15 | Confidence scoring, pattern detection working |
| **M4: Interactive** | Week 19 | DevShell refinement workflow complete |
| **M5: Intelligent** | Week 23 | LLM-powered discovery and refinement |
| **M6: Finalizable** | Week 28 | Full lifecycle: discovery → frozen → production |
| **M7: Libraries** | Week 36 | SymPy, pylatexenc, Math-Verify bundled |
| **M8: Maintainable** | Week 40 | Version monitoring, update proposals |

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| LLM latency | Slow discovery | Cache results, async proposals |
| Python API changes | Broken adapters | Maintainer agent, version pinning |
| Complex type mapping | Dialyzer errors | Gradual types, escape hatches |
| Large library APIs | Overwhelm | Focus mode, subset selection |

---

## Success Metrics

### Quantitative

- **Discovery time**: < 30 seconds for average library
- **Finalization time**: < 100 observations typically
- **Runtime overhead**: < 5% vs direct Snakepit
- **Config accuracy**: > 95% of functions work without modification

### Qualitative

- Developer experience feels like collaboration
- Zero manual config for priority libraries
- Adapters stay current with library updates
