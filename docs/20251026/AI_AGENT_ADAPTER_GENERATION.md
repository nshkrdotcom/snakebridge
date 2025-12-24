# AI Agent-Driven Python Adapter Generation Architecture

**Date**: 2025-10-26
**Status**: Design Phase
**Target**: Sonnet 5.0+ (2026)
**Purpose**: Scale to ANY Python library via AI-generated adapters

---

> Update (2025-12-23): SnakeBridge now uses a single adapter with manifest-driven wrappers. This doc remains a forward-looking design note; current integrations do not require per-library adapters.

## Vision

Enable external AI agents (Gemini, Claude, future models) to **automatically generate, test, and refine** Python adapters for SnakeBridge, allowing integration with arbitrary Python libraries without manual adapter writing.

**Key Principle**: SnakeBridge provides the **control plane**, AI agents provide the **generation intelligence**.

---

## The Problem: Adapter Explosion

### Current State (Manual)
- Each Python library needs an adapter with tools like:
  - `describe_library` - Introspect module schema
  - `call_python` - Execute functions/methods
  - `handle_types` - Convert Python ↔ Elixir types
- Writing adapters manually doesn't scale to 100s of libraries

### The Solution (AI-Assisted)
- **SnakeBridge provides**: Control API, validation, testing harness
- **AI agent provides**: Code generation, refinement, documentation
- **Result**: Automated adapter factory with human-in-the-loop quality control

---

## Architecture: Control Plane for External AI Agents

```
┌─────────────────────────────────────────────────────────────────┐
│  External AI Agent (Gemini/Claude/Future Model)                 │
│  - Generates Python adapter code                                │
│  - Writes tests                                                 │
│  - Refines based on feedback                                    │
│  - Writes documentation                                         │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ Uses Control API
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│  SnakeBridge Control Plane (Mix Tasks + API)                    │
│                                                                  │
│  1. Package Discovery                                           │
│     mix snakebridge.agent.discover <package> --llm <provider>   │
│     → Agent queries PyPI, analyzes package                      │
│     → Returns structured package metadata                       │
│                                                                  │
│  2. Adapter Generation                                          │
│     mix snakebridge.agent.generate <package> --llm <provider>   │
│     → Agent generates Python adapter code                       │
│     → Saves to priv/python/adapters/<package>.py               │
│                                                                  │
│  3. Test Generation                                             │
│     mix snakebridge.agent.test <package>                        │
│     → Agent generates Elixir + Python tests                     │
│     → Validates adapter works                                   │
│                                                                  │
│  4. Validation & Refinement Loop                                │
│     mix snakebridge.agent.validate <package>                    │
│     → Runs tests, collects failures                             │
│     → Agent refines code based on errors                        │
│     → Iterates until all tests pass                             │
│                                                                  │
│  5. Documentation Generation                                    │
│     mix snakebridge.agent.document <package>                    │
│     → Agent writes guides, examples, API docs                   │
│                                                                  │
│  6. Publishing                                                  │
│     mix snakebridge.agent.publish <package>                     │
│     → Commits adapter to registry                               │
│     → Makes available to all SnakeBridge users                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Control API Specification

### 1. Package Metadata API

**Purpose**: AI agent discovers Python package details

**Mix Task**: `mix snakebridge.agent.discover <package> --llm <provider>`

**API Endpoint**: `SnakeBridge.Agent.discover(package, llm: :gemini | :claude)`

**Input**: Package name (e.g., "demo", "langchain")

**Output**: Structured package metadata
```elixir
%{
  package_name: "demo-ai",           # PyPI package name
  import_name: "demo",               # Python import name
  version: "2.5.0",                  # Latest or specified version
  source_url: "https://github.com/...",
  requires_python: ">=3.8",
  dependencies: ["openai", "anthropic"],

  # Agent-discovered structure
  key_classes: ["Predict", "ChainOfThought", "ReAct"],
  key_functions: ["configure", "evaluate"],
  has_streaming: true,
  complexity_score: 7,  # 1-10, affects generation strategy

  # For validation
  test_imports: ["import demo", "demo.Predict"],
  quickstart_code: "predictor = demo.Predict('q -> a')"
}
```

**Storage**: `config/snakebridge/packages/<package>.exs`

---

### 2. Adapter Generation API

**Purpose**: AI generates Python adapter implementing required tools

**Mix Task**: `mix snakebridge.agent.generate <package> --template <type>`

**API**: `SnakeBridge.Agent.generate_adapter(package, template: :basic | :streaming | :full)`

**Input**:
- Package metadata (from step 1)
- Template type (basic, streaming, advanced)
- LLM provider configuration

**Output**: Python adapter code
```python
# priv/python/adapters/demo_adapter.py
from snakepit_bridge.base_adapter_threaded import ThreadSafeAdapter, tool
import demo

class DemoAdapter(ThreadSafeAdapter):
    def __init__(self):
        super().__init__()
        self.instances = {}

    @tool
    def describe_library(self, ...):
        # Generated by AI
        # Introspects demo module
        ...

    @tool
    def call_python(self, ...):
        # Generated by AI
        # Handles demo-specific calling patterns
        ...
```

**Validation**:
- Syntax check (compile Python)
- Import check (can import required modules)
- Tool signature verification
- Type hint validation

---

### 3. Test Generation API

**Purpose**: AI generates comprehensive test suite

**Mix Task**: `mix snakebridge.agent.test <package> --scope <level>`

**Output**:
- `test/adapters/<package>_adapter_test.exs` (Elixir tests)
- `priv/python/adapters/tests/test_<package>.py` (Python tests)

**Test Coverage**:
```elixir
# Generated Elixir tests
defmodule SnakeBridge.Adapters.DemoTest do
  test "describe_library returns valid schema"
  test "call_python creates instances"
  test "call_python executes methods"
  test "error handling for missing modules"
  test "streaming support" (if applicable)
end
```

```python
# Generated Python tests
class TestDemoAdapter(unittest.TestCase):
    def test_describe_library_returns_schema(self):
        # Agent generates realistic tests
        ...

    def test_call_python_with_predict(self):
        # Agent understands Demo API
        ...
```

---

### 4. Validation & Refinement Loop API

**Purpose**: Iterative improvement until tests pass

**Mix Task**: `mix snakebridge.agent.refine <package> --max-iterations 5`

**Flow**:
```
1. Run tests → Collect failures
2. Send failures to AI agent
3. Agent generates fixes
4. Apply fixes
5. Repeat until tests pass or max iterations
```

**API**:
```elixir
SnakeBridge.Agent.refine_adapter(package, opts) do
  # Returns refinement history
  [
    %{iteration: 1, tests_passing: 3, tests_failing: 7, changes: "..."},
    %{iteration: 2, tests_passing: 8, tests_failing: 2, changes: "..."},
    %{iteration: 3, tests_passing: 10, tests_failing: 0, status: :complete}
  ]
end
```

---

### 5. Package Configuration Schema

**File**: `config/snakebridge/python_packages.exs`

```elixir
# Python packages configuration for SnakeBridge adapters

[
  # First entry: Demo
  %{
    # PyPI metadata
    package_name: "demo-ai",
    import_name: "demo",
    version: "2.5.0",  # Latest as of 2025-10-26
    source: "https://github.com/stanfordnlp/demo",
    pypi_url: "https://pypi.org/project/demo-ai/",

    # Installation
    install_command: "pip install demo-ai==2.5.0",
    requires_python: ">=3.8,<4.0",
    dependencies: [
      "openai>=1.0.0",
      "anthropic>=0.3.0",
      "requests>=2.28.0",
      "backoff>=2.0.0"
    ],

    # SnakeBridge adapter config
    adapter_module: "snakebridge_adapters.demo_adapter",
    adapter_class: "DemoAdapter",
    supports_streaming: true,
    complexity: :high,  # :low | :medium | :high

    # Discovery hints for AI agent
    primary_classes: ["Predict", "ChainOfThought", "ReAct", "ProgramOfThought"],
    primary_functions: ["configure", "evaluate"],

    # Testing
    test_imports: ["import demo", "demo.Predict"],
    smoke_test: "demo.Predict('question -> answer')",

    # Documentation
    description: "Demo: Programming—not prompting—Foundation Models",
    docs_url: "https://demo-docs.vercel.app/",

    # Agent generation config
    generation_strategy: :iterative_refinement,
    max_refinement_iterations: 5,
    llm_provider: :claude,  # :gemini | :claude

    # Status tracking
    adapter_status: :planned,  # :planned | :generating | :testing | :complete
    last_generated: nil,
    tests_passing: nil
  },

  # Future packages...
  %{
    package_name: "langchain",
    # ... similar structure
  }
]
```

---

## Control Plane Components to Build

### Phase 1: Package Management (No AI Yet)

**File**: `lib/snakebridge/package_registry.ex`
```elixir
defmodule SnakeBridge.PackageRegistry do
  def list_packages()
  def get_package(name)
  def add_package(metadata)
  def update_package_status(name, status)
end
```

**File**: `lib/mix/tasks/snakebridge/package/list.ex`
```bash
mix snakebridge.package.list
# Lists all configured packages and their status
```

**File**: `lib/mix/tasks/snakebridge/package/add.ex`
```bash
mix snakebridge.package.add demo --version 2.5.0
# Adds package to config/snakebridge/python_packages.exs
```

---

### Phase 2: Agent Control Interface

**File**: `lib/snakebridge/agent/protocol.ex`
```elixir
defmodule SnakeBridge.Agent.Protocol do
  @moduledoc """
  Protocol for external AI agents to interact with SnakeBridge.

  Provides structured API for:
  - Requesting adapter generation
  - Submitting generated code
  - Running validation
  - Receiving feedback
  - Publishing completed adapters
  """

  @type generation_request :: %{
    package: String.t(),
    metadata: map(),
    template: :basic | :streaming | :full,
    constraints: keyword()
  }

  @type generation_response :: %{
    adapter_code: String.t(),
    test_code: String.t(),
    confidence: float(),
    warnings: [String.t()]
  }

  @callback request_generation(generation_request()) :: generation_response()
  @callback validate_adapter(String.t()) :: {:ok, results :: map()} | {:error, term()}
  @callback submit_refinement(package :: String.t(), fixes :: String.t()) :: :ok | {:error, term()}
end
```

---

### Phase 3: Validation Harness

**File**: `lib/snakebridge/agent/validator.ex`
```elixir
defmodule SnakeBridge.Agent.Validator do
  @doc """
  Validates AI-generated Python adapter code.

  Returns detailed feedback for refinement.
  """
  def validate_adapter(package_name, adapter_code) do
    %{
      syntax_valid: check_python_syntax(adapter_code),
      imports_work: check_imports(adapter_code, package_name),
      tools_registered: check_tool_registration(adapter_code),
      types_correct: check_type_hints(adapter_code),
      tests_passing: run_generated_tests(package_name),

      # Feedback for AI refinement
      errors: [...],
      warnings: [...],
      suggestions: [...]
    }
  end
end
```

---

### Phase 4: Template System (For AI Context)

**File**: `priv/templates/python_adapter_template.py.eex`
```python
"""
Python adapter for <%= package_name %> - Generated by AI Agent
Package: <%= pypi_package %>
Version: <%= version %>
"""

from snakepit_bridge.base_adapter_threaded import ThreadSafeAdapter, tool
import <%= import_name %>

class <%= adapter_class %>(ThreadSafeAdapter):
    def __init__(self):
        super().__init__()
        self.instances = {}
        self.session_state = {}

    @tool(description="Introspect <%= package_name %> library schema")
    def describe_library(self, module_path: str, discovery_depth: int = 2) -> dict:
        """
        AI AGENT: Implement introspection for <%= package_name %>

        Requirements:
        - Return schema with classes, methods, functions
        - Include type information
        - Handle errors gracefully
        - Max depth: discovery_depth

        Expected output format:
        {
            "library_version": "...",
            "classes": {...},
            "functions": {...}
        }
        """
        # AI GENERATES THIS CODE
        pass

    @tool(description="Execute <%= package_name %> code dynamically")
    def call_python(self, module_path: str, function_name: str,
                   args: list, kwargs: dict) -> dict:
        """
        AI AGENT: Implement dynamic execution for <%= package_name %>

        Requirements:
        - If function_name == "__init__": Create instance, return instance_id
        - Otherwise: Call method/function, return result
        - Handle <%= package_name %>-specific calling patterns
        - Proper error handling

        Expected output:
        {
            "success": true/false,
            "result": ...,  (or "instance_id": ...)
            "error": ... (if failed)
        }
        """
        # AI GENERATES THIS CODE
        pass

# AI AGENT: Add any <%= package_name %>-specific helper methods
```

**AI receives**: Template + package metadata + constraints
**AI returns**: Completed adapter code

---

## Control API: Mix Tasks for AI Agents

### 1. Discovery Control

```bash
# AI agent calls this (or API equivalent)
mix snakebridge.agent.discover demo \
  --llm claude \
  --output config/snakebridge/packages/demo.json
```

**What it does**:
1. Accepts package name
2. Calls external LLM (gemini_ex or codex_sdk) via configured provider
3. LLM queries PyPI, GitHub, docs
4. Returns structured metadata
5. Saves to config file
6. Returns JSON for agent to parse

**Output**:
```json
{
  "status": "success",
  "package": {
    "package_name": "demo-ai",
    "version": "2.5.0",
    ...
  },
  "saved_to": "config/snakebridge/packages/demo.json"
}
```

---

### 2. Generation Control

```bash
mix snakebridge.agent.generate demo \
  --llm claude \
  --template full \
  --output priv/python/adapters/demo_adapter.py
```

**What it does**:
1. Loads package metadata
2. Loads template
3. Sends to LLM with prompt:
   ```
   Generate a Snakepit adapter for Demo.
   Template: <template_code>
   Package info: <metadata>
   Constraints: <validation_rules>
   ```
4. Receives generated code
5. **Validates syntax** (parse Python)
6. **Saves to file**
7. Returns validation results

**Output**:
```json
{
  "status": "generated",
  "file": "priv/python/adapters/demo_adapter.py",
  "validation": {
    "syntax_valid": true,
    "imports_valid": false,
    "errors": ["Module 'demo' not found - needs installation"]
  }
}
```

---

### 3. Testing Control

```bash
mix snakebridge.agent.test demo \
  --generate-tests \
  --run-tests \
  --feedback
```

**What it does**:
1. AI generates test suite (or loads existing)
2. Runs Python tests: `pytest priv/python/adapters/tests/test_demo.py`
3. Runs Elixir tests: `mix test test/adapters/demo_test.exs`
4. Collects results
5. Returns structured feedback for AI refinement

**Output**:
```json
{
  "python_tests": {
    "total": 12,
    "passed": 10,
    "failed": 2,
    "failures": [
      {
        "test": "test_describe_library_schema",
        "error": "KeyError: 'Predict'",
        "traceback": "..."
      }
    ]
  },
  "elixir_tests": {
    "total": 8,
    "passed": 8,
    "failed": 0
  },
  "suggestions": [
    "describe_library missing 'Predict' class in response",
    "Add error handling for missing classes"
  ]
}
```

---

### 4. Refinement Loop Control

```bash
mix snakebridge.agent.refine demo \
  --llm claude \
  --max-iterations 5 \
  --auto-commit
```

**What it does**:
```
Loop (max 5 iterations):
  1. Run tests
  2. If all pass → DONE
  3. If failures → Send to AI with context:
     - Previous code
     - Test failures
     - Error messages
     - Validation feedback
  4. AI generates fixes
  5. Apply fixes
  6. Repeat
```

**Output**:
```json
{
  "iterations": 3,
  "final_status": "complete",
  "tests_passing": "20/20",
  "history": [
    {"iteration": 1, "passing": 12, "changes": "Added error handling"},
    {"iteration": 2, "passing": 18, "changes": "Fixed type conversion"},
    {"iteration": 3, "passing": 20, "changes": "Added streaming support"}
  ]
}
```

---

### 5. Python Environment Setup Control

```bash
mix snakebridge.setup.python \
  --package demo \
  --install-deps
```

**What it does**:
1. Creates virtual environment (if needed)
2. Installs package from config: `pip install demo-ai==2.5.0`
3. Installs Snakepit dependencies: `pip install grpcio protobuf`
4. Registers adapter with Snakepit
5. Validates installation

**Output**:
```json
{
  "venv_created": true,
  "venv_path": ".venv",
  "packages_installed": ["demo-ai==2.5.0", "grpcio", "protobuf"],
  "adapter_registered": true,
  "smoke_test_passed": true
}
```

---

## LLM Provider Interface

**File**: `lib/snakebridge/agent/llm_provider.ex`

```elixir
defmodule SnakeBridge.Agent.LLMProvider do
  @moduledoc """
  Abstraction over different LLM providers.

  Supports: Gemini (via gemini_ex), Claude (via codex_sdk)
  """

  @callback generate(prompt :: String.t(), opts :: keyword()) ::
    {:ok, response :: String.t()} | {:error, term()}

  @callback generate_structured(prompt :: String.t(), schema :: map(), opts :: keyword()) ::
    {:ok, structured_data :: map()} | {:error, term()}
end
```

**File**: `lib/snakebridge/agent/providers/gemini.ex`
```elixir
defmodule SnakeBridge.Agent.Providers.Gemini do
  @behaviour SnakeBridge.Agent.LLMProvider

  def generate_structured(prompt, schema, opts) do
    # Uses gemini_ex with structured output
    # Returns parsed, validated data
  end
end
```

**File**: `lib/snakebridge/agent/providers/claude.ex`
```elixir
defmodule SnakeBridge.Agent.Providers.Claude do
  @behaviour SnakeBridge.Agent.LLMProvider

  def generate_structured(prompt, schema, opts) do
    # Uses codex_sdk with JSON schema
    # Returns parsed, validated data
  end
end
```

---

## Prompt Templates

**File**: `priv/prompts/discover_package.md.eex`
```markdown
# Task: Discover Python Package Metadata

Package Name: <%= package_name %>

## Instructions

Query PyPI and GitHub to gather comprehensive metadata for this package.

## Required Information

1. PyPI package name (may differ from import name)
2. Latest stable version
3. GitHub repository URL
4. Python version requirements
5. Core dependencies
6. Main classes and functions (from documentation)
7. Whether it supports streaming/async

## Output Format

Return a JSON object matching this schema:
{
  "package_name": "string",
  "import_name": "string",
  "version": "semver",
  ...
}

Be accurate and verify information from official sources.
```

**File**: `priv/prompts/generate_adapter.md.eex`
```markdown
# Task: Generate Snakepit Adapter for <%= package_name %>

## Context

You're creating a Python adapter that allows Elixir code to call <%= package_name %> functions.

## Package Information
<%= Jason.encode!(package_metadata, pretty: true) %>

## Template
```python
<%= File.read!("priv/templates/python_adapter_template.py.eex") %>
```

## Requirements

1. Implement `describe_library(module_path, depth)`:
   - Use Python's `inspect` module
   - Introspect <%= import_name %> package
   - Return schema with classes, methods, type hints

2. Implement `call_python(module_path, function_name, args, kwargs)`:
   - Handle `__init__` → create instance, store it, return instance_id
   - Handle methods → retrieve instance, call method, return result
   - Handle <%= package_name %>-specific calling patterns

3. Error Handling:
   - Wrap all calls in try/except
   - Return {"success": false, "error": "..."}

4. Type Safety:
   - Add type hints
   - Validate arguments
   - Convert types as needed

## Constraints

- Must work with Snakepit's tool registry
- Must be thread-safe
- Must handle sessions correctly
- Code must be production-ready

Generate complete, working code. No placeholders.
```

---

## Validation Schema

**File**: `lib/snakebridge/agent/validation_schema.ex`

```elixir
defmodule SnakeBridge.Agent.ValidationSchema do
  @doc """
  Schema for validating AI-generated adapters
  """

  def adapter_requirements do
    %{
      # Code structure
      has_class: true,
      inherits_from: "ThreadSafeAdapter",
      has_init: true,

      # Required tools
      required_tools: ["describe_library", "call_python"],

      # Tool signatures
      tool_signatures: %{
        "describe_library" => %{
          params: ["module_path", "discovery_depth"],
          returns: "dict"
        },
        "call_python" => %{
          params: ["module_path", "function_name", "args", "kwargs"],
          returns: "dict"
        }
      },

      # Quality checks
      has_docstrings: true,
      has_type_hints: true,
      has_error_handling: true,

      # Testing
      min_test_coverage: 80,
      required_test_cases: [
        "test_describe_library",
        "test_call_python_init",
        "test_call_python_method",
        "test_error_handling"
      ]
    }
  end
end
```

---

## Agent Interaction Protocol (JSON-RPC Style)

**External agent** (running separately) talks to SnakeBridge via:

### Option A: Mix Task IPC
```bash
# Agent executes Mix tasks, parses JSON output
result=$(mix snakebridge.agent.generate demo --llm claude --format json)
echo $result | jq '.validation.errors'
```

### Option B: HTTP API (Future)
```elixir
# If we add Phoenix server
POST /api/agent/generate
{
  "package": "demo",
  "llm_provider": "claude",
  "template": "full"
}

Response:
{
  "adapter_code": "...",
  "validation": {...}
}
```

### Option C: Elixir API (Programmatic)
```elixir
# Agent running in Elixir (via Port/Node)
{:ok, result} = SnakeBridge.Agent.generate_adapter("demo",
  llm: SnakeBridge.Agent.Providers.Claude,
  template: :full
)
```

---

## File Structure (After Implementation)

```
lib/snakebridge/
├── agent/
│   ├── protocol.ex           # Agent interaction protocol
│   ├── validator.ex          # Validation harness
│   ├── llm_provider.ex       # LLM abstraction
│   ├── providers/
│   │   ├── gemini.ex         # gemini_ex integration
│   │   └── claude.ex         # codex_sdk integration
│   └── refinement_loop.ex    # Iterative improvement
│
├── package_registry.ex        # Package metadata management
│
lib/mix/tasks/snakebridge/
├── agent/
│   ├── discover.ex           # AI-assisted package discovery
│   ├── generate.ex           # AI-assisted adapter generation
│   ├── test.ex               # Run validation tests
│   ├── refine.ex             # Refinement loop
│   └── publish.ex            # Publish to registry
│
├── package/
│   ├── list.ex               # List packages
│   ├── add.ex                # Add package config
│   └── remove.ex             # Remove package
│
├── setup/
│   └── python.ex             # Setup Python environment

priv/
├── templates/
│   ├── python_adapter_template.py.eex
│   ├── python_tests_template.py.eex
│   └── elixir_tests_template.exs.eex
│
├── prompts/
│   ├── discover_package.md.eex
│   ├── generate_adapter.md.eex
│   ├── generate_tests.md.eex
│   └── refine_code.md.eex
│
├── python/
│   └── adapters/
│       ├── demo_adapter.py       # AI-generated
│       ├── langchain_adapter.py  # AI-generated
│       └── tests/
│           ├── test_demo.py      # AI-generated
│           └── test_langchain.py # AI-generated

config/snakebridge/
├── python_packages.exs         # Package registry
└── agent_config.exs            # AI agent configuration
```

---

## Why This Design Works

### Separation of Concerns

**SnakeBridge Provides** (Deterministic):
- Validation rules
- Testing harness
- Template structure
- API contracts
- Error feedback loops

**AI Agent Provides** (Creative):
- Code generation
- Type inference
- Error fixing
- Documentation writing
- Test case generation

### Future-Proof

- **Sonnet 5.0** (2026): Better code generation, deeper understanding
- **Future models**: Plug in via provider interface
- **Specialized models**: Use different LLMs for different tasks
  - Gemini for package discovery (web search)
  - Claude for code generation (better at code)

### Quality Control

```
AI generates → SnakeBridge validates → Fails → Feedback to AI → Refine
                                    → Passes → Human review → Publish
```

Human always in the loop for final approval.

---

## Implementation Phases

### Phase 1: Control Plane (Now - Week 1)
- [x] Package config schema
- [ ] PackageRegistry module
- [ ] mix snakebridge.package.* tasks
- [ ] Validation harness
- [ ] Template system

### Phase 2: LLM Integration (Week 2)
- [ ] Add gemini_ex dependency
- [ ] Add codex_sdk dependency
- [ ] LLMProvider behaviour
- [ ] Gemini provider implementation
- [ ] Claude provider implementation
- [ ] Prompt templates

### Phase 3: Agent Control Tasks (Week 3)
- [ ] mix snakebridge.agent.discover
- [ ] mix snakebridge.agent.generate
- [ ] mix snakebridge.agent.test
- [ ] mix snakebridge.agent.refine
- [ ] JSON output formatting

### Phase 4: Validation & Testing (Week 4)
- [ ] Python syntax validator
- [ ] Import checker
- [ ] Test runner integration
- [ ] Feedback parser
- [ ] Refinement loop logic

### Phase 5: First Adapter (Week 5)
- [ ] Run full pipeline for Demo
- [ ] Generate demo_adapter.py via AI
- [ ] Refine until tests pass
- [ ] Document the process
- [ ] Create reusable playbook

---

## Success Criteria

**For v0.2.0** (AI-Assisted Adapter Generation):
- [ ] Can generate adapter for ANY Python package
- [ ] AI-generated code passes validation
- [ ] Refinement loop achieves 90%+ test pass rate
- [ ] 5 example adapters completed (demo, langchain, transformers, numpy, pandas)
- [ ] Documentation for running agent pipeline

**For v1.0** (Production Agent Factory):
- [ ] Community can submit package requests
- [ ] Automated adapter generation + review
- [ ] Adapter registry with 50+ packages
- [ ] Quality metrics and versioning

---

## Current Status

**What we have**: Complete Elixir control plane ✅
**What we need**: Agent control interface, LLM integration, validation harness
**Blockers**: None - can start building control plane now
**When AI helps**: After control plane is ready (Phase 2+)

**This document**: Blueprint for scaling to ANY Python library via AI assistance.

---

**Next immediate steps**: Build Phase 1 (Control Plane) - no AI yet, just the infrastructure.
