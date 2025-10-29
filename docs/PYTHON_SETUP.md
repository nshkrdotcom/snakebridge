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
./scripts/setup_python.sh
```

This script:
1. ✅ Creates `.venv/` if it doesn't exist
2. ✅ Installs all required dependencies
3. ✅ Configures paths automatically
4. ✅ Detects existing Snakepit venv

**Done!** Skip to [Verification](#verification).

---

## Manual Setup

### Step 1: Create Virtual Environment

```bash
# Navigate to project root
cd /path/to/snakebridge

# Create venv
python3 -m venv .venv
```

This creates `.venv/` directory containing isolated Python environment.

### Step 2: Install Dependencies

```bash
# Install Snakepit dependencies (gRPC, protobuf, numpy, etc.)
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

# Install SnakeBridge Python adapter
cd priv/python
../../.venv/bin/pip install -e .
cd ../..
```

**What gets installed?**
- `grpcio` >= 1.60.0 - gRPC communication
- `protobuf` >= 4.25.0 - Protocol buffers
- `numpy` >= 1.21.0 - Scientific computing (required by Snakepit serialization)
- `psutil` >= 5.9.0 - Process management
- `orjson` >= 3.9.0 - Fast JSON serialization
- OpenTelemetry packages - Telemetry/observability

### Step 3: Configure Snakepit

Tell Snakepit which Python to use:

```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
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
# Should print: ✓ gRPC: 1.76.0 (or similar)

# Verify Protobuf
.venv/bin/python3 -c "import google.protobuf; print('✓ Protobuf installed')"
# Should print: ✓ Protobuf installed

# Verify NumPy
.venv/bin/python3 -c "import numpy; print('✓ NumPy:', numpy.__version__)"
# Should print: ✓ NumPy: 2.3.4 (or similar)

# Verify SnakeBridge adapter
.venv/bin/python3 -c "from snakebridge_adapter.adapter import SnakeBridgeAdapter; print('✓ Adapter ready')"
# Should print: ✓ Adapter ready
```

### Check Configuration

```bash
# Check SNAKEPIT_PYTHON is set
echo $SNAKEPIT_PYTHON
# Should print: /path/to/.venv/bin/python3

# Verify it's executable
$SNAKEPIT_PYTHON --version
# Should print: Python 3.x.x

# Test import through configured Python
$SNAKEPIT_PYTHON -c "import grpc; print('OK')"
# Should print: OK
```

### Run Tests

```bash
# Mock tests (no Python needed)
mix test
# All tests should pass

# Real Python integration tests
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
mix test --only real_python
# Should pass if environment is configured correctly
```

---

## Configuration

### Environment Variables

**`SNAKEPIT_PYTHON`** (Required for real Python execution)
- **Purpose**: Tells Snakepit which Python interpreter to use
- **Format**: Absolute path to Python executable
- **Example**: `/home/user/projects/snakebridge/.venv/bin/python3`
- **Set in**: Shell rc file, .envrc, or .env

**`PYTHONPATH`** (Usually auto-configured)
- **Purpose**: Python module search path
- **Format**: Colon-separated paths (Linux/macOS) or semicolon (Windows)
- **Auto-set by**: `setup_python.sh` and `example_helpers.exs`
- **Example**: `/path/to/snakebridge/priv/python:/path/to/snakepit/priv/python`

### Elixir Configuration

```elixir
# config/config.exs
import Config

# For real Python execution (not mocks)
config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitAdapter

# Snakepit pool configuration
config :snakepit,
  pooling_enabled: true,
  pool_config: %{pool_size: 2}

# Environment-specific overrides
import_config "#{config_env()}.exs"
```

```elixir
# config/dev.exs - use mocks in development by default
config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitMock  # Fast, no Python needed

# config/prod.exs - use real Python in production
config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitAdapter
```

---

## Common Scenarios

### Scenario 1: New Developer Joining Project

```bash
# Clone repo
git clone https://github.com/yourorg/snakebridge.git
cd snakebridge

# Install Elixir deps
mix deps.get

# Setup Python (one command)
./scripts/setup_python.sh

# Configure environment
echo 'export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3' >> ~/.bashrc
source ~/.bashrc

# Verify
mix test
```

### Scenario 2: Using SnakeBridge as a Dependency

```bash
# Your project
cd my_project
mix deps.get

# Setup Python from SnakeBridge dependency
./deps/snakebridge/scripts/setup_python.sh

# Or manually
python3 -m venv .venv
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

# Configure
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# Use in your code
mix run my_script.exs
```

### Scenario 3: CI/CD Pipeline

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '28'

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.9'

      - name: Install dependencies
        run: |
          mix deps.get
          python3 -m venv .venv
          .venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

      - name: Run tests
        run: |
          export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
          mix test --only integration
```

### Scenario 4: Docker Container

```dockerfile
FROM elixir:1.18-alpine

# Install Python
RUN apk add --no-cache python3 py3-pip

# Create app directory
WORKDIR /app

# Copy application
COPY . .

# Install Elixir deps
RUN mix deps.get

# Setup Python venv
RUN python3 -m venv /app/.venv && \
    /app/.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt && \
    cd priv/python && /app/.venv/bin/pip install -e . && cd ../..

# Configure Python path
ENV SNAKEPIT_PYTHON=/app/.venv/bin/python3

# Run
CMD ["mix", "run", "--no-halt"]
```

### Scenario 5: Multiple Projects Sharing Snakepit

```bash
# Create shared venv in Snakepit repo
cd ~/projects/snakepit
python3 -m venv .venv
.venv/bin/pip install -r priv/python/requirements.txt

# Project A uses it
cd ~/projects/project_a
export SNAKEPIT_PYTHON=~/projects/snakepit/.venv/bin/python3
mix run

# Project B uses it
cd ~/projects/project_b
export SNAKEPIT_PYTHON=~/projects/snakepit/.venv/bin/python3
mix run
```

---

## Troubleshooting

### "ModuleNotFoundError: No module named 'grpc'"

**Symptom**:
```
Python gRPC server process exited with status 1 during startup
Traceback (most recent call last):
  File ".../grpc_server.py", line 11, in <module>
    import grpc
ModuleNotFoundError: No module named 'grpc'
```

**Cause**: Dependencies not installed, or wrong Python being used.

**Solution**:
```bash
# Check which Python is configured
echo $SNAKEPIT_PYTHON
# Should point to venv Python

# If not set
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# Verify dependencies in venv
.venv/bin/python3 -c "import grpc; print('OK')"

# If fails, install dependencies
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt
```

### "error: externally-managed-environment"

**Symptom**:
```bash
$ pip3 install grpcio
error: externally-managed-environment

× This environment is externally managed
```

**Cause**: Trying to use system pip (forbidden on modern systems).

**Solution**: Use virtual environment:
```bash
# Create venv
python3 -m venv .venv

# Use venv pip
.venv/bin/pip install grpcio

# Or run setup script
./scripts/setup_python.sh
```

### "Python gRPC server process exited with status 1"

**Symptom**: Snakepit starts but Python workers crash immediately.

**Causes & Solutions**:

1. **SNAKEPIT_PYTHON not set**:
   ```bash
   export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
   ```

2. **Dependencies missing**:
   ```bash
   .venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt
   ```

3. **Wrong Python version** (need 3.9+):
   ```bash
   python3 --version  # Should be 3.9 or higher
   ```

4. **PYTHONPATH issues**:
   ```bash
   # Check PYTHONPATH includes SnakeBridge adapter
   echo $PYTHONPATH
   # Should include: /path/to/snakebridge/priv/python
   ```

### "no process: the process is not alive"

**Symptom**:
```
** (EXIT) no process: the process is not alive or there's no process currently associated with the given name
```

**Cause**: Snakepit Pool failed to start or Python worker crashed.

**Solution**:
```bash
# 1. Verify Python setup
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
.venv/bin/python3 -c "import grpc; print('OK')"

# 2. Run test with verbose output
mix test test/integration/real_python_test.exs --trace

# 3. Check Snakepit logs for Python errors
# Look for "Python gRPC server process exited" messages
```

### Virtual environment not activating

**Symptom**: After running `source .venv/bin/activate`, imports still fail.

**Cause**: Don't need to activate for SnakeBridge! Just set `SNAKEPIT_PYTHON`.

**Solution**:
```bash
# DON'T do this:
source .venv/bin/activate  # Not needed!

# DO this instead:
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
mix run example.exs
```

**Why?** Snakepit spawns Python subprocesses. It needs the Python path, not an activated environment in your shell.

### Dependencies installed but still not found

**Symptom**: Dependencies are in venv but Python can't import them.

**Cause**: Using system Python instead of venv Python.

**Solution**:
```bash
# Check where packages are
.venv/bin/pip list | grep grpc
# Should show: grpcio 1.76.0

# Verify SNAKEPIT_PYTHON points to venv
echo $SNAKEPIT_PYTHON
realpath $SNAKEPIT_PYTHON
# Should be: /path/to/snakebridge/.venv/bin/python3

# If wrong, fix it
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

---

## Platform-Specific Notes

### Linux (Ubuntu/Debian)

**Modern versions** (Ubuntu 24.04+, Debian 12+) **require venv**:
```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

**Older versions** allow system pip (not recommended):
```bash
pip3 install --user grpcio protobuf
```

### macOS

**With Homebrew Python**:
```bash
# Python 3 from Homebrew
brew install python@3.11

# Create venv
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

**With system Python**:
```bash
# macOS Monterey+ includes Python 3
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

### Windows

**With Python from python.org**:
```powershell
# Create venv
python -m venv .venv

# Activate
.venv\Scripts\activate

# Install
pip install -r requirements.txt

# Configure (PowerShell)
$env:SNAKEPIT_PYTHON = "$PWD\.venv\Scripts\python.exe"
```

**With WSL2** (Recommended):
```bash
# Use Linux instructions inside WSL2
wsl
cd /mnt/c/projects/snakebridge
python3 -m venv .venv
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

### Docker/Containers

**Alpine Linux**:
```dockerfile
RUN apk add --no-cache python3 py3-pip && \
    python3 -m venv /app/.venv && \
    /app/.venv/bin/pip install -r requirements.txt
ENV SNAKEPIT_PYTHON=/app/.venv/bin/python3
```

**Debian/Ubuntu**:
```dockerfile
RUN apt-get update && apt-get install -y python3 python3-venv python3-pip && \
    python3 -m venv /app/.venv && \
    /app/.venv/bin/pip install -r requirements.txt
ENV SNAKEPIT_PYTHON=/app/.venv/bin/python3
```

---

## Best Practices

### 1. One venv per project

```bash
# Good: Each project has its own venv
~/projects/project_a/.venv
~/projects/project_b/.venv

# Avoid: Shared system-wide venv (conflicts)
```

### 2. Pin dependency versions

```
# deps/snakepit/priv/python/requirements.txt
grpcio==1.76.0      # Good: specific version
protobuf>=4.25.0    # OK: minimum version
numpy               # Avoid: unpinned (can break)
```

### 3. Commit .gitignore, not .venv

```gitignore
# .gitignore
.venv/           # Never commit venv
__pycache__/
*.pyc
```

### 4. Document Python version

```markdown
# README.md
## Requirements
- Python 3.9+ (tested with 3.11)
- Elixir 1.18+
```

### 5. Use direnv for auto-config

```bash
# .envrc
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# Auto-loads when you cd into directory
direnv allow
```

---

## Additional Resources

- **SnakeBridge Examples**: [examples/QUICKSTART.md](../examples/QUICKSTART.md)
- **Test Setup**: [test/integration/README.md](../test/integration/README.md)
- **Python venv docs**: https://docs.python.org/3/library/venv.html
- **PEP 668**: https://peps.python.org/pep-0668/ (Why system pip is locked)
- **Snakepit README**: `deps/snakepit/README.md`

---

## Quick Reference Card

```bash
# Setup
python3 -m venv .venv
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

# Configure
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3

# Verify
.venv/bin/python3 -c "import grpc; print('OK')"
echo $SNAKEPIT_PYTHON

# Test
mix test                      # Mocks (fast)
mix test --only real_python   # Real Python
```

---

**Need more help?** Open an issue at https://github.com/nshkrdotcom/snakebridge/issues
