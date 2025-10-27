# SnakeBridge Quick Start

## Try It NOW (No Setup)

```bash
# See SnakeBridge API in action (uses mocks, no Python needed)
mix run examples/api_demo.exs
```

**This works immediately** - demonstrates all SnakeBridge features using mock data.

---

## Use With REAL Python (5 minute setup)

### Step 1: Install Python Dependencies

```bash
pip3 install grpcio protobuf
```

### Step 2: Configure for Live Mode

**Option A: Environment Variable** (Quick)
```bash
SNAKEBRIDGE_LIVE=true mix run examples/api_demo.exs
```

**Option B: Config File** (Persistent)
```elixir
# Create config/dev.secret.exs (not committed)
import Config

config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitAdapter  # Use real Snakepit
```

Then:
```bash
mix run examples/json_integration/example.exs
```

### Step 3: Verify Setup

```bash
# Check Python environment
python3 -c "import grpc; print('gRPC:', grpc.__version__)"
python3 -c "import google.protobuf; print('Protobuf: OK')"

# Check SnakeBridge adapter
cd priv/python
python3 -c "from snakebridge_adapter import SnakeBridgeAdapter; print('Adapter: OK')"

# Run Python tests
python3 tests/test_snakebridge_adapter.py
# Should see: Ran 12 tests ... OK
```

### Step 4: Run Live Example

```bash
cd ../..  # Back to project root
mix run examples/json_integration/example.exs
```

**Should work with real Python's json module!**

---

## Current Status

✅ **Mock Mode**: Works NOW (run `api_demo.exs`)
🔲 **Live Mode**: Needs `pip3 install grpcio protobuf`

**The choice**: Examples can work BOTH ways depending on configuration!
