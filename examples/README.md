# SnakeBridge Examples

This directory contains working examples demonstrating SnakeBridge functionality.

---

## Running the Examples

### 1. API Demo (No Python Required)

Shows SnakeBridge's API and code generation without executing Python code.

```bash
mix run examples/api_demo.exs
```

**What it demonstrates**:
- Configuration structure
- Code generation (viewing generated AST)
- Type system mappings
- Name transformations (Python → Elixir)
- Config validation
- Cache system
- Public API overview

**Duration**: ~1 second
**Requirements**: None (works with all Elixir code, no Python needed)

---

### 2. Mock Example (Simulated Python)

Shows the complete workflow using mocks to simulate Python responses.

```bash
# Currently not working - mocks not available in dev environment
# See test suite instead: mix test
```

**Status**: Tests demonstrate this functionality
**See**: `test/integration/end_to_end_test.exs` for full workflow tests

---

### 3. JSON Integration (Real Python)

**Status**: Requires Snakepit + Python setup
**File**: `examples/json_integration/example.exs`

**Setup required**:
```bash
# 1. Install Python dependencies
pip3 install grpcio protobuf

# 2. Install SnakeBridge adapter
cd priv/python
pip3 install -e .
cd ../..

# 3. Configure Snakepit in config/runtime.exs
# (See docs/20251026/COMPLETE_USAGE_EXAMPLE.md)

# 4. Run example
mix run examples/json_integration/example.exs
```

**What it demonstrates**:
- Real Python library discovery
- Real code execution via Snakepit's gRPC
- JSON encoding/decoding roundtrip
- Error handling
- Session management

---

## Example Output

### API Demo Output

```
🐍 SnakeBridge API Demonstration
============================================================

📋 Demo 1: Configuration Structure
------------------------------------------------------------
Created config for Python module: json
Functions: 2
Classes: 0

🏗️  Demo 2: Code Generation
------------------------------------------------------------
Generated Elixir module code:

defmodule DSPy.JsonModule do
  @moduledoc "Elixir wrapper for json..."
  @python_path "json"
  @type t :: {session_id :: String.t(), instance_id :: String.t()}

  def create(args \\ %{}, opts \\ []) do
    SnakeBridge.Runtime.create_instance(@python_path, args, ...)
  end
  ...

🔧 Demo 3: Type System
------------------------------------------------------------
Python type mappings:
  Python int    → Elixir :integer
  Python str    → Elixir :binary
  Python list   → Elixir [:integer]
  Python dict   → Elixir %{binary() => term()}

✅ Demo 5: Configuration Validation
------------------------------------------------------------
✓ Configuration is valid

💾 Demo 6: Cache System
------------------------------------------------------------
Config hash: 7ded4abd...
✓ Config cached
✓ Config loaded from cache
✓ Cache integrity verified

📚 Demo 7: Public API Overview
------------------------------------------------------------
SnakeBridge provides three main functions:
1. SnakeBridge.discover(module_path, opts)
2. SnakeBridge.generate(config)
3. SnakeBridge.integrate(module_path, opts)

✅ API Demo Complete!
```

---

## Next Steps

To run examples with REAL Python:

1. **Read the setup guide**: `docs/20251026/COMPLETE_USAGE_EXAMPLE.md`
2. **Install Python adapter**: See "Setup" section above
3. **Configure Snakepit**: Update config files
4. **Run integration tests**: `mix test --include real_python`

---

## Example Directory Structure

```
examples/
├── README.md                      # This file
├── api_demo.exs                   # ✅ Works now (no Python)
├── simple_mock_example.exs        # 🔲 Needs test environment
└── json_integration/
    ├── example.exs                # 🔲 Needs Snakepit setup
    └── README.md                  # Setup instructions
```

---

## For Developers

### Creating New Examples

1. Create a new `.exs` file in `examples/`
2. Use `#!/usr/bin/env elixir` shebang
3. Make it runnable with `mix run examples/your_example.exs`
4. Add clear output showing what's happening
5. Update this README

### Testing Examples

```bash
# Run all examples
for f in examples/*.exs; do
  echo "Running $f..."
  mix run "$f" || echo "Failed: $f"
done
```

---

**Current Status**: API demo working ✅ | Real Python examples pending Snakepit setup 🔲
