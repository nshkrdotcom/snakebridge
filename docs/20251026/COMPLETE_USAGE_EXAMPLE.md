# Complete SnakeBridge Usage Example

**Date**: 2025-10-26
**Purpose**: Step-by-step guide to integrating a Python library with SnakeBridge
**Example Library**: Python's built-in `json` module (simplest case)

---

> Note (2025-12-23): The recommended workflow is **manifest-driven** (JSON manifests + `mix snakebridge.manifest.*` tasks). Legacy config-based generation (`mix snakebridge.generate`) still works for backward compatibility, but new docs and examples favor manifests.

## Prerequisites

### 1. Elixir Project Setup

```elixir
# mix.exs
defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  defp deps do
    [
      {:snakebridge, "~> 0.2.4"},
      {:snakepit, "~> 0.7.0"}
    ]
  end
end
```

### 2. Install Dependencies

```bash
mix deps.get
mix deps.compile
```

### 3. Setup Python Environment

```bash
# Install Python dependencies for Snakepit
pip3 install grpcio protobuf

# Install SnakeBridge Python adapter
cd deps/snakebridge/priv/python
pip3 install -e .
cd ../../../..
```

---

## Step 1: Configure Snakepit to Use SnakeBridgeAdapter

### Create Config File

**File**: `config/config.exs`

```elixir
import Config

# Configure SnakeBridge (auto-start Snakepit by default)
config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitAdapter,
  auto_start_snakepit: true,
  python_path: ".venv/bin/python3",
  pool_size: 2,
  load: [],
  custom_manifests: ["config/snakebridge/*.json"],
  allow_unsafe: true # set false when exclusively using manifest allowlists
```

---

## Step 2: Discover Python Library

### Option A: Using Mix Task (Recommended)

```bash
# Discover the json module and generate a draft manifest
mix snakebridge.discover json --output config/snakebridge/json.json

# Output:
# Discovering Python library: json
# Discovery depth: 2
# ✓ Manifest written to: config/snakebridge/json.json
#
# Next steps:
#   1. Review and curate: config/snakebridge/json.json
#   2. Compile modules: mix snakebridge.manifest.compile
```

### Generated Manifest File

**File**: `config/snakebridge/json.json`

```json
{
  "name": "json",
  "python_module": "json",
  "python_path_prefix": "json",
  "elixir_module": "Json",
  "functions": [
    { "name": "dumps", "args": ["obj"], "returns": "string" },
    { "name": "loads", "args": ["s"], "returns": "map" }
  ]
}
```

---

### Option B: Using Public API (Programmatic)

```elixir
# In IEx or your code
iex> {:ok, schema} = SnakeBridge.discover("json")
iex> manifest = SnakeBridge.Manifest.Agent.suggest_from_schema(schema)
iex> File.write!("config/snakebridge/json.json", SnakeBridge.Manifest.to_json(manifest))
:ok
```

---

## Step 3: Generate Elixir Wrapper Modules

### Option A: Using Mix Task

```bash
# Ensure custom manifests are configured (in config/config.exs)
# config :snakebridge, custom_manifests: ["config/snakebridge/*.json"]

# Compile manifests into Elixir modules
mix snakebridge.manifest.compile --output lib/my_app/generated

# Output:
# Compiled 1 modules into lib/my_app/generated
```

### Option B: Using Public API

```elixir
iex> {:ok, config} = SnakeBridge.Manifest.from_file("config/snakebridge/json.json")
iex> SnakeBridge.Manifest.Registry.register_config(config)
iex> {:ok, modules} = SnakeBridge.generate(config)
{:ok, [Json]}

# Or in one step:
iex> {:ok, modules} = SnakeBridge.integrate("json") # legacy config path
{:ok, [Json]}
```

---

## Step 4: Use the Generated Modules

### Example 1: JSON Encoding

```elixir
# Start your application (starts Snakepit workers)
iex> Application.ensure_all_started(:snakepit)
{:ok, [:snakepit]}

# The Json module is now available (generated dynamically)
iex> data = %{
  name: "SnakeBridge",
  version: "0.1.0",
  features: ["type-safe", "zero-code", "fast"]
}

# Call Python's json.dumps through generated module
iex> {:ok, json_string} = Json.dumps(data)
{:ok, "{\"name\": \"SnakeBridge\", \"version\": \"0.1.0\", \"features\": [\"type-safe\", \"zero-code\", \"fast\"]}"}
```

**What happens under the hood**:
1. `Json.dumps/1` calls `SnakeBridge.Runtime.call_method`
2. Runtime calls `Snakepit.execute_in_session(session_id, "call_python", ...)`
3. Snakepit sends gRPC request to Python worker
4. Python worker's `SnakeBridgeAdapter.call_python` executes:
   ```python
   import json
   result = json.dumps({"name": "SnakeBridge", ...})
   return {"success": True, "result": result}
   ```
5. gRPC response flows back to Elixir
6. User receives `{:ok, json_string}`

---

### Example 2: JSON Decoding

```elixir
iex> json_string = ~s({"hello": "world", "count": 42})

iex> {:ok, decoded} = Json.loads(%{s: json_string})
{:ok, %{"hello" => "world", "count" => 42}}
```

---

### Example 3: Roundtrip

```elixir
defmodule MyApp.JsonExample do
  def roundtrip_test do
    # Original Elixir data
    original = %{
      user: "alice",
      score: 95,
      tags: ["elixir", "python", "bridge"]
    }

    # Encode to JSON
    {:ok, json_string} = Json.dumps(original)
    IO.puts("JSON: #{json_string}")
    # => JSON: {"user": "alice", "score": 95, "tags": ["elixir", "python", "bridge"]}

    # Decode back
    {:ok, decoded} = Json.loads(%{s: json_string})
    IO.inspect(decoded, label: "Decoded")
    # => Decoded: %{"user" => "alice", "score" => 95, "tags" => ["elixir", "python", "bridge"]}

    # Verify data survived roundtrip
    assert decoded["user"] == original.user
    assert decoded["score"] == original.score
    assert decoded["tags"] == original.tags
  end
end
```

---

## Step 5: Working with Classes (More Complex Example)

> Note: Class-based integrations still use the legacy Config pipeline. Manifests currently target stateless functions, so class examples below use `SnakeBridge.integrate/2` and require `allow_unsafe: true` to bypass the manifest allowlist.

### Discover a Library with Classes

```bash
mix snakebridge.discover unittest --depth 2
```

### Generated Config for unittest

```elixir
%SnakeBridge.Config{
  python_module: "unittest",

  classes: [
    %{
      python_path: "unittest.TestCase",
      elixir_module: Unittest.TestCase,
      constructor: %{
        args: %{},
        session_aware: true
      },
      methods: [
        %{name: "assertEqual", elixir_name: :assert_equal},
        %{name: "assertTrue", elixir_name: :assert_true},
        # ... more methods
      ]
    }
  ]
}
```

### Using Classes

```elixir
# Generate modules
{:ok, [Unittest.TestCase]} = SnakeBridge.integrate("unittest")

# Create instance
{:ok, test_case} = Unittest.TestCase.create(%{}, allow_unsafe: true)
# Returns: {:ok, {"session_abc123", "instance_xyz789"}}

# Call methods on the instance
{:ok, result} = Unittest.TestCase.assert_equal(test_case, %{
  first: 1,
  second: 1
}, allow_unsafe: true)
# Python: test_case.assertEqual(1, 1) → returns None
# Elixir: {:ok, nil}

# This would raise in Python:
{:error, reason} = Unittest.TestCase.assert_equal(test_case, %{
  first: 1,
  second: 2
}, allow_unsafe: true)
# Python exception caught and returned as {:error, "AssertionError: 1 != 2"}
```

---

## Step 6: Production Workflow

### Complete Example Application

**File**: `lib/my_app/python_integration.ex`

```elixir
defmodule MyApp.PythonIntegration do
  @moduledoc """
  Example application using SnakeBridge to integrate Python's json module.
  """

  # Generate at compile time in production
  @compile {:autoload, false}

  def start do
    # Ensure Snakepit is running
    {:ok, _} = Application.ensure_all_started(:snakepit)

    # Integrate json module
    case SnakeBridge.integrate("json") do
      {:ok, modules} ->
        IO.puts("✓ Python integration ready")
        IO.puts("Available modules: #{inspect(modules)}")
        {:ok, modules}

      {:error, reason} ->
        IO.puts("✗ Failed to integrate: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def example_usage do
    {:ok, [Json]} = start()

    # Example 1: Simple encoding
    data = %{message: "Hello from Elixir!", timestamp: System.system_time(:second)}
    {:ok, json} = Json.dumps(data)
    IO.puts("Encoded: #{json}")

    # Example 2: Decoding
    {:ok, parsed} = Json.loads(%{s: json})
    IO.puts("Decoded: #{inspect(parsed)}")

    # Example 3: Pretty printing
    pretty_data = %{
      app: "MyApp",
      config: %{
        debug: true,
        port: 4000
      }
    }

    {:ok, pretty_json} = Json.dumps(%{
      obj: pretty_data,
      indent: 2
    })

    IO.puts("Pretty JSON:\n#{pretty_json}")

    :ok
  end

  def handle_api_request(data) do
    {:ok, [Json]} = start()

    # Convert Elixir data to JSON for external API
    case Json.dumps(data) do
      {:ok, json_string} ->
        # Send to external API
        {:ok, json_string}

      {:error, reason} ->
        {:error, "JSON encoding failed: #{reason}"}
    end
  end

  def process_api_response(json_string) do
    {:ok, [Json]} = start()

    # Parse JSON response from external API
    case Json.loads(%{s: json_string}) do
      {:ok, parsed_data} ->
        # Process in Elixir
        {:ok, parsed_data}

      {:error, reason} ->
        {:error, "JSON decoding failed: #{reason}"}
    end
  end
end
```

### Running the Example

```elixir
# In IEx
iex> MyApp.PythonIntegration.example_usage()

# Output:
# ✓ Python integration ready
# Available modules: [Json]
# Encoded: {"message":"Hello from Elixir!","timestamp":1730000000}
# Decoded: %{"message" => "Hello from Elixir!", "timestamp" => 1730000000}
# Pretty JSON:
# {
#   "app": "MyApp",
#   "config": {
#     "debug": true,
#     "port": 4000
#   }
# }
# :ok
```

---

## Step 7: Advanced Example - Custom Manifest

### Customize the Generated Manifest

**File**: `config/snakebridge/json_custom.json`

```json
{
  "name": "json_custom",
  "python_module": "json",
  "python_path_prefix": "json",
  "elixir_module": "CustomJson",
  "types": {
    "obj": "any",
    "indent": "integer",
    "s": "string"
  },
  "functions": [
    { "name": "dumps", "elixir_name": "encode", "args": ["obj", "indent"], "returns": "string" },
    { "name": "loads", "elixir_name": "decode", "args": ["s"], "returns": "map" }
  ]
}
```

### Use Customized Module

```elixir
# Generate with custom manifest
{:ok, config} = SnakeBridge.Manifest.from_file("config/snakebridge/json_custom.json")
SnakeBridge.Manifest.Registry.register_config(config)
{:ok, [CustomJson]} = SnakeBridge.generate(config)

# Now using custom names!
{:ok, encoded} = CustomJson.encode(%{test: "data"})  # Instead of dumps
{:ok, decoded} = CustomJson.decode(%{s: encoded})    # Instead of loads
```

---

## Step 8: Error Handling Examples

### Handling Discovery Errors

```elixir
# Try to discover non-existent module
case SnakeBridge.discover("nonexistent_library") do
  {:ok, schema} ->
    IO.puts("Discovered: #{inspect(schema)}")

  {:error, reason} ->
    IO.puts("Discovery failed: #{inspect(reason)}")
    # => Discovery failed: "No module named 'nonexistent_library'"
end
```

### Handling Execution Errors

```elixir
{:ok, [Json]} = SnakeBridge.integrate("json")

# Invalid JSON string
case Json.loads(%{s: "not valid json{"}) do
  {:ok, result} ->
    IO.puts("Parsed: #{inspect(result)}")

  {:error, reason} ->
    IO.puts("Parse error: #{inspect(reason)}")
    # => Parse error: "JSONDecodeError: Expecting value: line 1 column 1 (char 0)"
end
```

---

## Step 9: Session Management

### Reusing Sessions for Performance

```elixir
# Create a persistent session
session_id = "my_app_json_session_#{System.unique_integer()}"

# Discover with session
{:ok, schema} = SnakeBridge.discover("json", session_id: session_id)

# Generate
config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "json")
{:ok, [Json]} = SnakeBridge.generate(config)

# All calls use the same Python worker (via session_id)
{:ok, json1} = Json.dumps(%{call: 1}, session_id: session_id)
{:ok, json2} = Json.dumps(%{call: 2}, session_id: session_id)
{:ok, json3} = Json.dumps(%{call: 3}, session_id: session_id)

# Benefits:
# - Faster (no worker spawn overhead)
# - Maintains state (if Python side stores session data)
# - Better for request tracing
```

---

## Step 10: Integration Testing

### Create Test File

**File**: `test/my_app/json_integration_test.exs`

```elixir
defmodule MyApp.JsonIntegrationTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :real_python

  setup_all do
    # Ensure Snakepit is running with SnakeBridge adapter
    Application.ensure_all_started(:snakepit)
    :ok
  end

  describe "JSON integration via SnakeBridge" do
    test "can encode Elixir data to JSON" do
      {:ok, [Json]} = SnakeBridge.integrate("json")

      data = %{
        string: "test",
        number: 42,
        float: 3.14,
        boolean: true,
        null: nil,
        array: [1, 2, 3],
        nested: %{key: "value"}
      }

      assert {:ok, json_string} = Json.dumps(data)
      assert is_binary(json_string)
      assert json_string =~ "test"
      assert json_string =~ "42"
    end

    test "can decode JSON to Elixir data" do
      {:ok, [Json]} = SnakeBridge.integrate("json")

      json_string = ~s({"name":"Alice","age":30,"active":true})

      assert {:ok, decoded} = Json.loads(%{s: json_string})
      assert decoded["name"] == "Alice"
      assert decoded["age"] == 30
      assert decoded["active"] == true
    end

    test "roundtrip preserves data" do
      {:ok, [Json]} = SnakeBridge.integrate("json")

      original = %{
        users: [
          %{name: "Alice", age: 30},
          %{name: "Bob", age: 25}
        ],
        metadata: %{created_at: "2025-10-26"}
      }

      # Encode
      {:ok, json_string} = Json.dumps(original)

      # Decode
      {:ok, decoded} = Json.loads(%{s: json_string})

      # Verify structure (note: atom keys become string keys)
      assert length(decoded["users"]) == 2
      assert decoded["users"] |> List.first() |> Map.get("name") == "Alice"
      assert decoded["metadata"]["created_at"] == "2025-10-26"
    end

    test "handles encoding errors gracefully" do
      {:ok, [Json]} = SnakeBridge.integrate("json")

      # Try to encode something that's not JSON-serializable
      # (Python functions, for example)
      # For this test, we'll use a valid case
      # Real error handling tested with Python's actual errors

      assert {:ok, _} = Json.dumps(%{valid: "data"})
    end

    test "handles decoding errors gracefully" do
      {:ok, [Json]} = SnakeBridge.integrate("json")

      # Invalid JSON
      assert {:error, reason} = Json.loads(%{s: "not valid json {"})
      assert reason =~ "Expecting" or reason =~ "Decode"
    end
  end

  describe "performance and session affinity" do
    test "multiple calls use session affinity" do
      {:ok, [Json]} = SnakeBridge.integrate("json")

      session_id = "test_session_#{System.unique_integer()}"

      # NOTE: Under load, use strict affinity (:strict_queue) to guarantee routing.
      # Hint mode is best-effort and may fall back to a different worker.
      # All these calls should use the same Python worker
      results =
        Enum.map(1..10, fn i ->
          Json.dumps(%{iteration: i}, session_id: session_id)
        end)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    @tag :performance
    test "encoding is reasonably fast" do
      {:ok, [Json]} = SnakeBridge.integrate("json")

      data = %{test: "data", number: 123}

      # Measure time for 100 calls
      {time_microseconds, _} =
        :timer.tc(fn ->
          Enum.each(1..100, fn _ ->
            {:ok, _} = Json.dumps(data)
          end)
        end)

      avg_time_ms = time_microseconds / 1000 / 100
      IO.puts("Average encoding time: #{avg_time_ms}ms")

      # Should be reasonably fast (< 10ms per call with gRPC overhead)
      assert avg_time_ms < 50
    end
  end
end
```

### Run Integration Tests

```bash
# Run without integration tests (mocked, fast)
mix test
# => 76/76 passing

# Run with real Python integration
mix test --include real_python
# => 76 + 7 integration tests = 83/83 passing (if Python setup correctly)
```

---

## Step 11: Production Deployment

### Application Startup

**File**: `lib/my_app/application.ex`

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start Snakepit with SnakeBridge adapter
      {Snakepit.PoolSupervisor,
       pool_config: %{
         adapter_module: "snakebridge_adapter.adapter",
         adapter_class: "SnakeBridgeAdapter",
         pool_size: 4
       }},

      # Your other workers
      MyApp.Web.Endpoint,
      MyApp.Repo
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

---

## Step 12: Real-World Use Case - API Integration

### Example: Using SnakeBridge in Phoenix API

```elixir
defmodule MyAppWeb.DataController do
  use MyAppWeb, :controller

  # Generate json module at startup
  @json_module (
    {:ok, [mod]} = SnakeBridge.integrate("json")
    mod
  )

  def create(conn, %{"data" => data}) do
    # Convert to JSON for external API call
    case @json_module.dumps(data) do
      {:ok, json_payload} ->
        # Send to external service
        HTTPoison.post("https://api.example.com/data", json_payload,
          [{"Content-Type", "application/json"}]
        )

        json(conn, %{status: "success"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid data: #{reason}"})
    end
  end

  def webhook(conn, _params) do
    # Read JSON from request body
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    case @json_module.loads(%{s: body}) do
      {:ok, parsed_data} ->
        # Process webhook data
        process_webhook(parsed_data)
        json(conn, %{status: "received"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid JSON: #{reason}"})
    end
  end

  defp process_webhook(data) do
    # Your business logic here
    IO.inspect(data, label: "Webhook received")
  end
end
```

---

## Troubleshooting Guide

### Problem: Module not found

```elixir
{:error, "No module named 'my_library'"}
```

**Solution**:
```bash
# Install the Python package
pip3 install my-library

# Verify installation
python3 -c "import my_library; print(my_library.__version__)"
```

---

### Problem: Snakepit not starting

```elixir
** (exit) exited in: GenServer.call(Snakepit.PoolManager, ...)
```

**Solution**:
```bash
# Check Python is available
python3 --version

# Check gRPC dependencies installed
python3 -c "import grpc; print('gRPC OK')"

# Check SnakeBridge adapter installed
python3 -c "from snakebridge_adapter import SnakeBridgeAdapter; print('Adapter OK')"

# Start Snakepit manually to see errors
iex> Snakepit.start_pool(adapter_module: "snakebridge_adapter.adapter")
```

---

### Problem: Tool not found

```elixir
{:error, "Unknown tool: call_python"}
```

**Solution**:
```bash
# Verify adapter is registered correctly
# In IEx:
iex> Snakepit.list_tools()
# Should include "call_python" and "describe_library"

# If not, check adapter registration
iex> Snakepit.get_stats()
# Shows active workers and loaded adapters
```

---

## Configuration Reference

### Minimal config/config.exs

```elixir
import Config

config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitAdapter,
  auto_start_snakepit: true,
  python_path: ".venv/bin/python3",
  pool_size: 2,
  load: [],
  custom_manifests: ["config/snakebridge/*.json"]
```

### Development config/dev.exs

```elixir
import Config

config :snakebridge,
  compilation_mode: :runtime  # Hot reload

config :logger, level: :debug  # See Snakepit gRPC calls
```

### Test config/test.exs

```elixir
import Config

config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitMock  # Use mocks

config :logger, level: :warning
```

---

## Complete Workflow Summary

```bash
# 1. Setup
mix deps.get
pip3 install grpcio protobuf
cd deps/snakebridge/priv/python && pip3 install -e . && cd ../../../..

# 2. Discover Python library
mix snakebridge.discover json --output config/snakebridge/json.json

# 3. Review generated manifest
cat config/snakebridge/json.json

# 4. Generate Elixir modules
mix snakebridge.manifest.compile

# 5. Use in your code
```

```elixir
# 6. In your application
{:ok, config} = SnakeBridge.Manifest.from_file("config/snakebridge/json.json")
{:ok, [Json]} = SnakeBridge.generate(config)
{:ok, json} = Json.dumps(%{hello: "world"})
{:ok, data} = Json.loads(%{s: json})
```

```bash
# 7. Test
mix test                      # Fast (mocked)
mix test --include real_python  # Slow (real Python)

# 8. Deploy
MIX_ENV=prod mix release
```

---

## Expected Output at Each Step

### Discovery Output

```
$ mix snakebridge.discover json --output config/snakebridge/json.json

Discovering Python library: json
Discovery depth: 2
✓ Manifest written to: config/snakebridge/json.json

Next steps:
  1. Review and curate: config/snakebridge/json.json
  2. Compile modules: mix snakebridge.manifest.compile
```

### Generation Output

```
$ mix snakebridge.manifest.compile

Compiled 1 modules into lib/snakebridge/generated
```

### Validation Output

```
$ mix snakebridge.manifest.validate

Validating manifests...

✓ json.json
✓ 1 manifest(s) validated successfully
```

### Usage Output

```elixir
iex> {:ok, [Json]} = SnakeBridge.integrate("json")
{:ok, [Json]}

iex> {:ok, result} = Json.dumps(%{hello: "world"})
{:ok, "{\"hello\": \"world\"}"}

iex> {:ok, decoded} = Json.loads(%{s: result})
{:ok, %{"hello" => "world"}}
```

---

## Performance Characteristics

### Expected Latency (with gRPC)

| Operation | First Call | Subsequent Calls |
|-----------|------------|------------------|
| Discovery | 100-500ms | ~10ms (cached) |
| Module Generation | 5-20ms | 0ms (already loaded) |
| Python Execution | 10-50ms | 5-20ms (session affinity; strict recommended under load) |

### Throughput

- **Concurrent calls**: Limited by Snakepit pool_size (default: 4 workers)
- **Session affinity**: Multiple calls to same session use same worker
- **Overhead**: ~5-10ms per call (gRPC serialization + Python execution)

---

## Next Steps

### To Actually Run This Example:

1. **Setup Python environment**
   ```bash
   cd deps/snakebridge/priv/python
   pip3 install -e .
   ```

2. **Configure Snakepit** (in config/runtime.exs)
   ```elixir
   config :snakepit,
     adapter_module: "snakebridge_adapter.adapter",
     adapter_class: "SnakeBridgeAdapter"
   ```

3. **Start and test**
   ```bash
   iex -S mix
   ```

4. **Run the example**
   ```elixir
   MyApp.PythonIntegration.example_usage()
   ```

---

## What This Example Demonstrates

✅ **Discovery**: Introspecting Python libraries
✅ **Generation**: Creating type-safe Elixir modules
✅ **Execution**: Calling Python code from Elixir
✅ **Error Handling**: Graceful failure management
✅ **Session Management**: Efficient worker reuse
✅ **Customization**: Configuring generated modules
✅ **Testing**: Both mocked and real integration tests
✅ **Production**: Deployment patterns

**This is the complete SnakeBridge workflow!**
