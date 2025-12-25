# Integration Tests with Real Python

This directory contains integration tests that use **real Python execution** via Snakepit, not mocks.

## ⚠️ Prerequisites

### 1. Python Virtual Environment (REQUIRED)

**Why?** Modern systems (Ubuntu 24.04+, Debian 12+) forbid system-wide pip installs. You **MUST** use a virtual environment.

**Quick Setup**:
```bash
# From project root
./scripts/setup_python.sh
```

**Or manually**:
```bash
# Create venv
python3 -m venv .venv

# Install dependencies
.venv/bin/pip install -r ../deps/snakepit/priv/python/requirements.txt

# Install SnakeBridge adapter
cd priv/python
../../.venv/bin/pip install -e .
cd ../..
```

### 2. Configure Snakepit Python

Tests need to know which Python to use:

```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

**Tip**: Add to your shell rc file or use [direnv](https://direnv.net/):
```bash
echo 'export SNAKEPIT_PYTHON='$(pwd)'/.venv/bin/python3' >> .envrc
direnv allow
```

### 3. Verify Setup

```bash
# Check Python environment
.venv/bin/python3 -c "import grpc; print('✓ gRPC installed')"
.venv/bin/python3 -c "from snakebridge_adapter.adapter import SnakeBridgeAdapter; print('✓ Adapter ready')"

# Verify Snakepit can find Python
echo $SNAKEPIT_PYTHON
# Should print: /path/to/snakebridge/.venv/bin/python3
```

---

## Running Tests

### All Tests (Mocks Only)

```bash
# Runs fast - no Python needed
mix test
```

### Integration Tests (Real Python)

```bash
# Python config is automatic: tests pick SNAKEPIT_PYTHON if set, else ./.venv/bin/python3, else system python3
# Run integration tests (auto-starts a Snakepit pool via SnakeBridge.SnakepitTestHelper)
mix test --only integration

# Or run specific test file
mix test test/integration/real_python_test.exs --only real_python
```

### End-to-End Tests

```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
mix test test/integration/end_to_end_test.exs --only integration
```

---

## Test Categories

### Mock Tests (Default)
- **Location**: `test/unit/`, `test/snakebridge_api_test.exs`
- **Requirements**: None - uses `SnakeBridge.SnakepitMock`
- **Speed**: Fast (< 1 second)
- **Purpose**: Test Elixir logic without Python

### Integration Tests
- **Location**: `test/integration/end_to_end_test.exs`
- **Tag**: `@moduletag :integration`
- **Requirements**: Python venv + dependencies
- **Speed**: Slow (1-5 seconds)
- **Purpose**: Test full workflow with mocks

### Real Python Tests
- **Location**: `test/integration/real_python_test.exs`
- **Tag**: `@moduletag :real_python`
- **Requirements**: Python venv + dependencies + `SNAKEPIT_PYTHON`
- **Speed**: Very slow (5-10 seconds)
- **Purpose**: Verify actual Python execution works

---

## Test File Structure

```
test/
├── unit/                          # Fast unit tests (mocks)
│   ├── generator_test.exs
│   ├── config_test.exs
│   └── ...
├── integration/
│   ├── README.md                  # This file
│   ├── end_to_end_test.exs        # Full workflow (with mocks)
│   ├── real_python_test.exs       # Real Python execution
│   └── function_execution_test.exs
├── property/                      # Property-based tests
│   ├── config_properties_test.exs
│   └── type_mapper_properties_test.exs
└── support/
    ├── snakepit_mock.ex           # Mock Snakepit for tests
    └── test_fixtures.ex           # Shared test data
```

---

## Troubleshooting

### "ModuleNotFoundError: No module named 'grpc'"

**Problem**: Python dependencies not installed.

**Solution**:
```bash
# Run setup script
./scripts/setup_python.sh

# Or manually install
.venv/bin/pip install grpcio protobuf numpy
```

### "Python gRPC server process exited with status 1"

**Problem**: Snakepit can't find Python or `SNAKEPIT_PYTHON` not set.

**Solution**:
```bash
# Set environment variable
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# Verify it points to your venv Python
echo $SNAKEPIT_PYTHON
.venv/bin/python3 -c "import grpc; print('OK')"
```

### "no process: the process is not alive"

**Problem**: Snakepit Pool not started or Python worker crashed.

**Solution**:
```bash
# Check Python setup first
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
.venv/bin/python3 -c "from snakebridge_adapter.adapter import SnakeBridgeAdapter; print('OK')"

# Try running a single test with verbose output
mix test test/integration/real_python_test.exs --only real_python --trace
```

### "error: externally-managed-environment"

**Problem**: Trying to use system pip (not allowed on modern systems).

**Solution**: **Always use a virtual environment**:
```bash
python3 -m venv .venv
.venv/bin/pip install <package>
```

### Tests pass but Python features don't work

**Problem**: Tests use mocks by default.

**Solution**: Explicitly run with Python configured:
```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
mix test --only real_python
```

---

## Writing New Integration Tests

### Template for Real Python Tests

```elixir
defmodule MyApp.Integration.MyTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :real_python  # Mark as requiring real Python
  @moduletag :slow

  setup_all do
    # Switch to real adapter
    original = Application.get_env(:snakebridge, :snakepit_adapter)
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    on_exit(fn ->
      Application.put_env(:snakebridge, :snakepit_adapter, original)
    end)

    :ok
  end

  test "my real Python test" do
    # Your test here - uses real Snakepit
    {:ok, schema} = SnakeBridge.discover("json")
    assert is_map(schema)
  end
end
```

### Run Your Test

```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
mix test test/integration/my_test.exs --only real_python
```

---

## CI/CD Considerations

### GitHub Actions / CI

Integration tests with real Python need Python setup in CI:

```yaml
# .github/workflows/ci.yml
steps:
  - name: Set up Python
    uses: actions/setup-python@v4
    with:
      python-version: '3.9'

  - name: Create venv and install dependencies
    run: |
      python3 -m venv .venv
      .venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

  - name: Run integration tests
    run: |
      export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
      mix test --only integration
```

### Local Development

For convenience, add to `.envrc` (use with [direnv](https://direnv.net/)):

```bash
# .envrc
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

Then tests "just work":
```bash
direnv allow
mix test --only real_python
```

---

## Quick Reference

### Complete Setup

```bash
# 1. Create venv
python3 -m venv .venv

# 2. Install deps
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

# 3. Install adapter
cd priv/python && ../../.venv/bin/pip install -e . && cd ../..

# 4. Configure
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# 5. Test
mix test --only real_python
```

### Daily Workflow

```bash
# Once per terminal session
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# Run tests
mix test                      # Mocks only (fast)
mix test --only integration   # With real Python
mix test --only real_python   # Real Python only
```

---

## Need Help?

1. Check this README first
2. See [docs/PYTHON_SETUP.md](../docs/PYTHON_SETUP.md) for detailed Python setup guide
3. Check [examples/QUICKSTART.md](../examples/QUICKSTART.md) for working examples
4. Open an issue with your environment details
