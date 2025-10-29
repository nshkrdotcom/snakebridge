# SnakeBridge Quick Start

## Try It NOW (No Setup)

```bash
# See SnakeBridge API in action (uses mocks, no Python needed)
mix run examples/api_demo.exs
```

**This works immediately** - demonstrates all SnakeBridge features using mock data.

---

## Use With REAL Python

### Step 1: Install Python Dependencies (2 minutes)

**⚠️ IMPORTANT**: Modern Python requires a virtual environment. Do NOT use system pip.

**Option A: Automated Setup (Recommended)**
```bash
# From SnakeBridge project root
./scripts/setup_python.sh
```

This script automatically:
- Creates `.venv` if it doesn't exist
- Installs all required dependencies (grpcio, protobuf, numpy)
- Configures Python path for Snakepit

**Option B: Manual Setup**
```bash
# Create virtual environment
python3 -m venv .venv

# Activate it
source .venv/bin/activate  # Linux/macOS
# OR
.venv\Scripts\activate     # Windows

# Install dependencies
pip install grpcio protobuf numpy

# Configure Snakepit to use this Python
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

**Why venv?** Ubuntu 24.04+, Debian 12+, and other modern systems prevent system-wide pip installs (PEP 668). Always use a virtual environment.

### Step 2: Verify Installation

```bash
# Verify Python dependencies are installed
.venv/bin/python3 -c "import grpc; print('✓ gRPC:', grpc.__version__)"
.venv/bin/python3 -c "import google.protobuf; print('✓ Protobuf installed')"
.venv/bin/python3 -c "import numpy; print('✓ NumPy:', numpy.__version__)"

# Verify SnakeBridge adapter is available
.venv/bin/python3 -c "from snakebridge_adapter.adapter import SnakeBridgeAdapter; print('✓ SnakeBridge adapter ready')"
```

All checks should print ✓. If any fail, re-run setup.

### Step 3: Configure for Live Mode

**Option A: Environment Variable** (Quick, for one-off runs)
```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
mix run examples/api_demo.exs
```

**Option B: Config File** (Persistent)
```elixir
# Create config/dev.secret.exs (gitignored)
import Config

config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitAdapter  # Use real Snakepit instead of mock
```

Then run examples normally:
```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
mix run examples/json_integration/example.exs
```

### Step 4: Run Live Examples

```bash
# Ensure Python is configured
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# JSON example (uses Python's built-in json module)
elixir examples/live_demo.exs

# NumPy example (scientific computing)
elixir examples/numpy_live.exs

# Streaming example (GenAI adapter)
elixir examples/genai_streaming.exs
```

**Note**: Examples using `Mix.install` (like `live_demo.exs`) handle Python setup automatically via `example_helpers.exs`.

---

## Troubleshooting

### "ModuleNotFoundError: No module named 'grpc'"

**Problem**: Python dependencies not installed or wrong Python being used.

**Solution**:
```bash
# Check which Python Snakepit is using
echo $SNAKEPIT_PYTHON

# Should point to your venv Python, e.g., /path/to/.venv/bin/python3
# If not set or wrong, configure it:
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# Verify dependencies are in venv:
.venv/bin/python3 -c "import grpc; print('OK')"
```

### "error: externally-managed-environment"

**Problem**: Trying to use system pip (not allowed on modern systems).

**Solution**: Always use a virtual environment:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install grpcio protobuf numpy
```

### "Python gRPC server process exited with status 1"

**Problem**: Snakepit can't find Python or dependencies.

**Solution**:
```bash
# Set SNAKEPIT_PYTHON to your venv Python
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# Verify it works
$SNAKEPIT_PYTHON -c "import grpc; print('OK')"
```

### Examples don't run

**Problem**: Python environment not configured.

**Solution**: Most examples need `SNAKEPIT_PYTHON` set:
```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
elixir examples/live_demo.exs
```

---

## Quick Reference

### Complete Setup Sequence

```bash
# 1. Create venv
python3 -m venv .venv

# 2. Install dependencies
.venv/bin/pip install grpcio protobuf numpy

# 3. Configure environment
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# 4. Run example
elixir examples/live_demo.exs
```

### For Development

```bash
# Persist Python configuration
echo 'export SNAKEPIT_PYTHON='$(pwd)'/.venv/bin/python3' >> .envrc
# Use with direnv or source manually

# Run tests with real Python
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
mix test --only real_python
```

---

## Current Status

✅ **Mock Mode**: Works NOW with zero setup (run `api_demo.exs`)
✅ **Live Mode**: Requires Python venv + dependencies (2 min setup)

**The choice**: Examples can work BOTH ways depending on configuration!
