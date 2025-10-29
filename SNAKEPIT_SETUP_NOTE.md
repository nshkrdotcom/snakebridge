# Note for Snakepit README Update

**To Snakepit Maintainers**:

The Snakepit README currently references a setup script that doesn't exist in the hex package:

```bash
./deps/snakepit/scripts/setup_python.sh  # DOES NOT EXIST in hex package
```

## Recommended Fix

Update the installation section to:

```markdown
### 3. Install Python Dependencies

**IMPORTANT**: Modern systems require a virtual environment (PEP 668).

**Quick Setup**:
```bash
# Create virtual environment
python3 -m venv .venv

# Install dependencies
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

# Configure Snakepit to use venv Python
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

**Why venv?** Ubuntu 24.04+, Debian 12+, and other modern systems prevent system-wide pip installs.

**Verify Installation**:
```bash
.venv/bin/python3 -c "import grpc; print('✓ gRPC installed')"
echo $SNAKEPIT_PYTHON  # Should point to .venv/bin/python3
```

**For Developers** (working on Snakepit from source):
```bash
./scripts/setup_python.sh  # Only available in source repo
```
```

## Issue Location

`deps/snakepit/README.md` lines 31-42

## Why This Matters

Users following the README get immediate failures, causing confusion and frustration. Virtual environments are now mandatory on modern systems, so this should be the PRIMARY method, not a fallback.
