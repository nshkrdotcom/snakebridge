# Python Environment Setup for SnakeBridge

Complete guide to setting up Python for use with SnakeBridge and Snakepit.

---

## Table of Contents

- [Why Virtual Environments?](#why-virtual-environments)
- [Quick Setup](#quick-setup)
- [Manual Setup](#manual-setup)
- [Verification](#verification)
- [Configuration](#configuration)
- [Common Scenarios](#common-scenarios)
- [Troubleshooting](#troubleshooting)
- [Platform-Specific Notes](#platform-specific-notes)

---

## Why Virtual Environments?

### The Problem: System Python is Locked Down

**Modern Linux distributions prevent system-wide pip installs**:

```bash
$ pip3 install grpcio
error: externally-managed-environment

× This environment is externally managed
╰─> To install Python packages system-wide, try apt install python3-xyz
```

**Why?** [PEP 668](https://peps.python.org/pep-0668/) prevents pip from breaking system Python packages.

**Affected Systems**:
- Ubuntu 24.04+ (Noble)
- Debian 12+ (Bookworm)
- Fedora 38+
- Other modern distributions

**The Solution**: Virtual environments (`venv`) - isolated Python environments per project.

---

## Quick Setup

### Automated (Recommended)

```bash
# From SnakeBridge project root
mix snakebridge.setup --venv .venv
```

This task:
1. Creates `.venv/` if it doesn't exist
2. Installs Snakepit + SnakeBridge dependencies
3. Installs built-in manifest libraries (sympy, pylatexenc, math-verify)
4. Prints the required `SNAKEPIT_PYTHON` and `PYTHONPATH` exports

SnakeBridge can auto-start a Snakepit pool on the first real call (default `auto_start_snakepit: true`), but it still needs a Python interpreter with dependencies installed.

---

## Manual Setup

### Step 1: Create Virtual Environment

```bash
# Navigate to project root
cd /path/to/snakebridge

# Create venv
python3 -m venv .venv
```

### Step 2: Install Dependencies

```bash
# Install Snakepit dependencies (gRPC, protobuf, numpy, etc.)
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

# Install SnakeBridge Python adapter + built-in manifest libs
.venv/bin/pip install -r priv/python/requirements.snakebridge.txt
.venv/bin/pip install -e priv/python
```

### Optional: Install manifest packages via Mix

If you want to install packages based on the manifest registry (built-ins or custom), you can use:

```bash
mix snakebridge.manifest.install --load sympy,pylatexenc,math_verify --venv .venv --include_core
```

### Step 3: Configure Snakepit

Tell Snakepit which Python to use:

```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
export PYTHONPATH=$(pwd)/priv/python:$(pwd)/deps/snakepit/priv/python:$PYTHONPATH
```

**Make it persistent** (choose one):

**Option A: Shell RC File**
```bash
echo 'export SNAKEPIT_PYTHON=/path/to/snakebridge/.venv/bin/python3' >> ~/.bashrc
source ~/.bashrc
```

**Option B: direnv** (Recommended for development)
```bash
echo 'export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3' > .envrc
direnv allow
```

**Option C: .env file** (Load with `source .env`)
```bash
echo 'export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3' > .env
```

---

## Verification

### Check Dependencies

```bash
# Verify gRPC
.venv/bin/python3 -c "import grpc; print('✓ gRPC:', grpc.__version__)"

# Verify Protobuf
.venv/bin/python3 -c "import google.protobuf; print('✓ Protobuf installed')"

# Verify NumPy
.venv/bin/python3 -c "import numpy; print('✓ NumPy:', numpy.__version__)"

# Verify built-in manifest libraries
.venv/bin/python3 -c "import sympy; print('✓ SymPy:', sympy.__version__)"
.venv/bin/python3 -c "import pylatexenc; print('✓ pylatexenc:', pylatexenc.__version__)"
.venv/bin/python3 -c "import math_verify; print('✓ math_verify')"

# Verify SnakeBridge adapter
.venv/bin/python3 -c "from snakebridge_adapter.adapter import SnakeBridgeAdapter; print('✓ Adapter ready')"
```

### Check Configuration

```bash
# Check SNAKEPIT_PYTHON is set
echo $SNAKEPIT_PYTHON

# Verify it's executable
$SNAKEPIT_PYTHON --version

# Test import through configured Python
$SNAKEPIT_PYTHON -c "import grpc; print('OK')"
```

### Run Tests

```bash
# Mock tests (no Python needed)
mix test

# Real Python integration tests
mix test --only real_python
```

---

## Configuration

### Environment Variables

**`SNAKEPIT_PYTHON`** (Required for real Python execution)
- **Purpose**: Tells Snakepit which Python interpreter to use
- **Format**: Absolute path to Python executable
- **Example**: `/home/user/projects/snakebridge/.venv/bin/python3`

**`PYTHONPATH`** (Usually auto-configured)
- **Purpose**: Python module search path
- **Format**: Colon-separated paths (Linux/macOS) or semicolon (Windows)
- **Auto-set by**: `mix snakebridge.setup` and SnakeBridge's Python launcher
- **Example**: `/path/to/snakebridge/priv/python:/path/to/snakepit/priv/python`

### Elixir Configuration

```elixir
# config/config.exs
import Config

config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitAdapter,
  auto_start_snakepit: true,
  python_path: ".venv/bin/python3",
  pool_size: 2,
  load: [:sympy, :pylatexenc, :math_verify],
  custom_manifests: ["config/snakebridge/*.json"],
  allow_unsafe: false
```

---

## Common Scenarios

### I want to run the examples

```bash
mix snakebridge.setup --venv .venv
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
./examples/run_all.sh
```

### I want SnakeBridge to auto-start Snakepit

Default behavior already does this. If you disable it, you must start Snakepit yourself.

```elixir
config :snakebridge, auto_start_snakepit: false
```

---

## Troubleshooting

### "ModuleNotFoundError: No module named 'grpc'"

**Problem**: Python dependencies not installed or wrong Python being used.

**Solution**:
```bash
# Check which Python Snakepit is using
echo $SNAKEPIT_PYTHON

# Configure it if missing
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

### "Snakepit is not running (Snakepit.Pool not found)"

**Problem**: Auto-start disabled or Python unavailable.

**Solution**:
```bash
# Ensure auto-start is enabled
# config :snakebridge, auto_start_snakepit: true

# Ensure Python is configured
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

---

## Platform-Specific Notes

### Windows

- Use `;` instead of `:` in `PYTHONPATH`
- Use `python` instead of `python3` in venv creation

### macOS

- Use `python3 -m venv .venv` and ensure Homebrew Python is installed
- Use `export` commands in `.zshrc` or `.bash_profile`
