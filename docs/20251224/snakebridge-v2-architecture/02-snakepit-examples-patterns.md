# Snakepit Examples and Usage Patterns Research

**Research Date:** 2024-12-24
**Snakepit Version:** v0.7.1
**Purpose:** Design inputs for snakebridge v2 architecture

---

## Executive Summary

Snakepit is a battle-tested, production-ready Elixir library for managing Python processes via gRPC. This research documents its examples, adapter patterns, introspection capabilities, and usage patterns to inform snakebridge v2's redesign.

**Key Findings:**
1. **Adapter pattern is central** - Python code follows a decorator-based pattern with automatic tool discovery
2. **gRPC-first architecture** - Modern HTTP/2 protocol with streaming support
3. **Session-based state management** - Elixir owns all state, Python workers are stateless
4. **Bidirectional tool bridge** - Python can call Elixir tools and vice versa
5. **Comprehensive introspection** - Automatic parameter extraction from function signatures
6. **Handler-based organization** - Large adapters decompose into domain-specific handlers

---

## 1. Repository Structure

### Core Python Bridge Location
```
snakepit/
├── priv/python/
│   ├── grpc_server.py                      # Main gRPC server (stateless)
│   ├── grpc_server_threaded.py             # Threaded variant for Python 3.13+
│   ├── snakepit_bridge/
│   │   ├── __init__.py
│   │   ├── base_adapter.py                 # Base class all adapters inherit
│   │   ├── session_context.py              # Session management helper
│   │   ├── serialization.py                # Type serialization utilities
│   │   ├── heartbeat.py                    # Worker health monitoring
│   │   ├── telemetry/                      # Observability framework
│   │   └── adapters/
│   │       ├── template.py                 # Minimal template
│   │       └── showcase/
│   │           ├── showcase_adapter.py     # Reference implementation
│   │           └── handlers/               # Domain-specific handlers
│   │               ├── basic_ops.py
│   │               ├── binary_ops.py
│   │               ├── streaming_ops.py
│   │               ├── concurrent_ops.py
│   │               ├── session_ops.py
│   │               └── ml_workflow.py
│   └── tests/                              # Python unit tests
└── examples/                               # Elixir usage examples
```

---

## 2. Examples Found and What They Demonstrate

### 2.1 Basic gRPC Examples

#### `examples/grpc_basic.exs`
**Demonstrates:** Simple request/response patterns
```elixir
# 1. Simple ping command
Snakepit.execute("ping", %{})
#=> {:ok, %{"message" => "pong", "timestamp" => "..."}}

# 2. Echo with data
Snakepit.execute("echo", %{message: "Hello from gRPC!", timestamp: DateTime.utc_now()})
#=> {:ok, %{"echoed" => %{"message" => "Hello from gRPC!", ...}}}

# 3. Simple calculation
Snakepit.execute("add", %{a: 2, b: 2})
#=> {:ok, 4}

# 4. Adapter introspection
Snakepit.execute("adapter_info", %{})
#=> {:ok, %{"adapter_name" => "ShowcaseAdapter", "version" => "2.0.0", ...}}
```

**Key Lesson:** Dead simple API - `execute(tool_name, args)` is the core pattern.

---

#### `examples/grpc_sessions.exs`
**Demonstrates:** Session affinity and worker routing
```elixir
# Create session with worker affinity
session_id = "demo_session_1"

# All calls with same session_id prefer the same worker
for _ <- 1..5 do
  {:ok, _result} = Snakepit.execute_in_session(session_id, "ping", %{})
end

# Check which worker handled the session
{:ok, session} = Snakepit.Bridge.SessionStore.get_session(session_id)
session.last_worker_id  #=> "worker_123" (same across all calls)
```

**Key Lessons:**
- Sessions enable stateful workflows
- Worker affinity is automatic
- SessionStore is Elixir-owned (Python is stateless)

---

#### `examples/grpc_streaming.exs`
**Demonstrates:** Real-time streaming with progress updates
```elixir
# Stream progress in real-time
Snakepit.execute_stream("stream_progress", %{steps: 5, delay_ms: 250}, fn chunk ->
  IO.puts("Progress: #{chunk["progress"]}% - #{chunk["message"]}")
  # chunk = %{
  #   "step" => 3,
  #   "total" => 5,
  #   "progress" => 60.0,
  #   "message" => "Processing step 3/5",
  #   "elapsed_ms" => 750.0,
  #   "is_final" => false
  # }
end)
```

**Key Lessons:**
- Streaming is first-class (not an afterthought)
- Chunks have structured envelope: `is_final`, `progress`, metadata
- Callbacks receive decoded data incrementally

---

### 2.2 Bidirectional Tool Bridge

#### `examples/bidirectional_tools_demo.exs`
**Demonstrates:** Python calling Elixir tools and vice versa

**Elixir Side:**
```elixir
# Define Elixir tool
defmodule ElixirTools do
  def parse_json(params) do
    json_string = Map.get(params, "json_string", "{}")
    case Jason.decode(json_string) do
      {:ok, parsed} -> %{success: true, data: parsed, keys: Map.keys(parsed)}
      {:error, reason} -> %{success: false, error: inspect(reason)}
    end
  end
end

# Register for Python access
ToolRegistry.register_elixir_tool(
  session_id,
  "parse_json",
  &ElixirTools.parse_json/1,
  %{
    description: "Parse a JSON string and return analysis",
    exposed_to_python: true,
    parameters: [%{name: "json_string", type: "string", required: true}]
  }
)
```

**Python Side (`examples/python_elixir_tools_demo.py`):**
```python
# Discover available Elixir tools
ctx = SessionContext(stub, session_id)
print("Available Elixir tools:", list(ctx.elixir_tools.keys()))
#=> ['parse_json', 'calculate_fibonacci', 'process_list']

# Call Elixir tool from Python
result = ctx.call_elixir_tool('parse_json', json_string='{"test": true}')
#=> {'success': True, 'data': {'test': True}, 'keys': ['test']}

# Use tool proxy (even cleaner)
parse_json = ctx.elixir_tools["parse_json"]
result = parse_json(json_string='{"name": "test"}')
```

**Key Lessons:**
- **Truly bidirectional** - Both languages can call each other's tools
- Tool discovery is automatic via `ctx.elixir_tools`
- Tool proxies make Elixir tools feel like native Python functions
- Enables hybrid workflows: "Python ML → Elixir validation → Python processing"

---

### 2.3 Advanced Examples

#### `examples/snakepit_showcase/`
**Full Mix application demonstrating:**
- Binary data processing
- Concurrent operations
- ML workflows
- Session management
- Streaming operations
- Telemetry integration

#### `examples/snakepit_loadtest/`
**Load testing framework showing:**
- Pool scaling (100+ workers)
- Burst load patterns
- Stress testing
- Sustained load scenarios

#### `examples/dual_mode/`
**Worker profile demonstrations:**
- Process profile (GIL-safe, many processes)
- Thread profile (Python 3.13+ free-threading)
- Hybrid pool configurations

---

## 3. The Adapter Pattern - How Python Code Should Be Structured

### 3.1 Core Pattern: BaseAdapter + @tool Decorator

**Every adapter inherits from `BaseAdapter` and uses the `@tool` decorator:**

```python
from snakepit_bridge.base_adapter import BaseAdapter, tool

class MyAdapter(BaseAdapter):
    def __init__(self):
        super().__init__()
        # Optional: initialize resources
        self.session_context = None  # Will be set by framework

    @tool(description="Process text with various operations")
    def process_text(self, text: str, operation: str = "upper") -> dict:
        """Process text and return results."""
        operations = {
            "upper": lambda t: t.upper(),
            "lower": lambda t: t.lower(),
            "reverse": lambda t: t[::-1]
        }

        result = operations[operation](text)
        return {
            "original": text,
            "operation": operation,
            "result": result,
            "success": True
        }

    @tool(description="Add two numbers", supports_streaming=False)
    def add(self, a: float, b: float) -> float:
        """Add two numbers together."""
        return a + b

    @tool(description="Stream progress updates", supports_streaming=True)
    def stream_progress(self, steps: int = 5, delay_ms: int = 500):
        """Generate streaming progress updates."""
        for i in range(steps):
            yield {
                "step": i + 1,
                "total": steps,
                "progress": (i + 1) / steps * 100,
                "is_final": i == steps - 1
            }
            time.sleep(delay_ms / 1000.0)
```

### 3.2 Key Adapter Concepts

**1. Stateless by Design:**
```python
# ❌ WRONG - Don't store state in adapter
class BadAdapter(BaseAdapter):
    def __init__(self):
        super().__init__()
        self.user_data = {}  # Workers can be recycled!

    @tool(description="Store data")
    def store(self, key: str, value: Any):
        self.user_data[key] = value  # Lost on worker restart!

# ✅ CORRECT - Use SessionContext (Elixir-backed state)
class GoodAdapter(BaseAdapter):
    @tool(description="Store data")
    def store(self, key: str, value: Any):
        # State lives in Elixir's SessionStore
        self.session_context.call_elixir_tool('store_variable',
                                               key=key, value=value)
```

**2. Automatic Tool Discovery:**
```python
# BaseAdapter automatically discovers methods with @tool decorator
adapter = MyAdapter()
tools = adapter.get_tools()  # Returns list of ToolRegistration messages

# Each tool includes:
# - name: "process_text"
# - description: "Process text with various operations"
# - parameters: [ParameterSpec(name="text", type="str", required=True), ...]
# - supports_streaming: False
# - metadata: {"adapter_class": "MyAdapter", "module": "..."}
```

**3. Parameter Introspection:**
```python
# BaseAdapter extracts parameter info from function signatures
def _create_parameter_spec(self, name: str, param: inspect.Parameter):
    # Determines type from annotation
    param_type = 'str' if param.annotation == str else 'any'

    # Checks if required (no default value)
    required = param.default == inspect.Parameter.empty

    # Extracts default value if present
    default = param.default if param.default != inspect.Parameter.empty else None

    return ParameterSpec(
        name=name,
        type=param_type,
        required=required,
        default_value=default
    )
```

### 3.3 Handler-Based Organization (Advanced)

**For large adapters, use the handler pattern:**

```python
# showcase_adapter.py
from .handlers import BasicOpsHandler, StreamingOpsHandler, MLWorkflowHandler

class ShowcaseAdapter(BaseAdapter):
    def __init__(self):
        super().__init__()

        # Initialize domain-specific handlers
        self.handlers = {
            'basic': BasicOpsHandler(),
            'streaming': StreamingOpsHandler(),
            'ml': MLWorkflowHandler()
        }

        # Build unified tool registry
        self._handler_tools = {}
        for handler in self.handlers.values():
            self._handler_tools.update(handler.get_tools())

    # Expose handler tools as adapter tools
    @tool(description="Stream progress updates")
    def stream_progress(self, steps: int = 5):
        return self.handlers['streaming'].get_tools()['stream_progress'].func(
            self.session_context, steps=steps
        )
```

**Handler Example:**
```python
# handlers/basic_ops.py
from ..tool import Tool

class BasicOpsHandler:
    def get_tools(self) -> Dict[str, Tool]:
        return {
            "ping": Tool(self.ping),
            "echo": Tool(self.echo),
            "add": Tool(self.add),
        }

    def ping(self, ctx, message: str = "pong") -> Dict[str, str]:
        return {"message": message, "timestamp": str(time.time())}

    def add(self, ctx, a: float, b: float) -> float:
        return a + b
```

**Benefits:**
- ✅ Separation of concerns
- ✅ Easier testing
- ✅ Clear domain boundaries
- ✅ Shared utility code per domain

---

## 4. Common Usage Patterns

### 4.1 Session Context Access Pattern

```python
class MyAdapter(BaseAdapter):
    @tool(description="Access session state")
    def get_session_info(self) -> dict:
        # Session context is automatically set by framework
        return {
            "session_id": self.session_context.session_id,
            "request_metadata": self.session_context.request_metadata,
            # Access Elixir tools
            "available_elixir_tools": list(self.session_context.elixir_tools.keys())
        }

    @tool(description="Call Elixir from Python")
    def hybrid_processing(self, data: dict) -> dict:
        # Python processing
        python_result = self._process_locally(data)

        # Call Elixir for validation
        elixir_result = self.session_context.call_elixir_tool(
            'validate_schema',
            schema=python_result
        )

        return {"python": python_result, "elixir": elixir_result}
```

### 4.2 Binary Data Pattern

```python
@tool(description="Process binary data")
def process_image(self, data: bytes, operation: str = 'resize') -> dict:
    """Handle binary data like images, files, etc."""
    import hashlib

    checksum = hashlib.md5(data).hexdigest()
    size = len(data)

    # Process binary data
    if operation == 'checksum':
        return {"checksum": checksum, "size": size}
    elif operation == 'resize':
        # Use PIL/Pillow for actual image processing
        return {"status": "resized", "original_size": size}
```

**Elixir side:**
```elixir
# Binary parameters are sent as separate field
{:ok, result} = Snakepit.execute("process_image",
  %{operation: "checksum"},
  binary_parameters: %{"data" => image_binary}
)
```

### 4.3 Streaming Pattern

```python
from snakepit_bridge.adapters.showcase.tool import StreamChunk

@tool(description="Process large dataset", supports_streaming=True)
def process_dataset(self, file_path: str, chunk_size: int = 1000):
    """Stream processing results as they complete."""
    total_rows = 10000  # Determine from file
    processed = 0

    while processed < total_rows:
        # Process chunk
        rows_in_chunk = min(chunk_size, total_rows - processed)
        chunk_data = self._process_chunk(file_path, processed, rows_in_chunk)
        processed += rows_in_chunk

        # Yield streaming chunk
        yield StreamChunk(
            data={
                "processed_rows": processed,
                "total_rows": total_rows,
                "progress": processed / total_rows * 100,
                "chunk_result": chunk_data
            },
            is_final=(processed >= total_rows)
        )
```

### 4.4 Telemetry Pattern

```python
from snakepit_bridge import telemetry

@tool(description="Operation with telemetry")
def compute_heavy_task(self, data: dict) -> dict:
    correlation_id = telemetry.get_correlation_id()

    # Emit start event
    telemetry.emit(
        "tool.execution.start",
        {"system_time": time.time_ns()},
        {"tool": "compute_heavy_task"},
        correlation_id=correlation_id
    )

    # Use span for automatic timing
    with telemetry.span("heavy.computation", {"dataset_size": len(data)}, correlation_id):
        result = self._do_computation(data)

        # Emit custom metrics
        telemetry.emit(
            "computation.result_size",
            {"bytes": len(result)},
            {"tool": "compute_heavy_task"},
            correlation_id=correlation_id
        )

    return result
```

### 4.5 Error Handling Pattern

```python
@tool(description="Safe operation with error handling")
def safe_operation(self, data: dict) -> dict:
    try:
        result = self._risky_operation(data)
        return {"success": True, "result": result}
    except ValueError as e:
        # Structured error response
        return {
            "success": False,
            "error": "Invalid input",
            "error_type": "ValueError",
            "details": str(e)
        }
    except Exception as e:
        # Generic error with logging
        logger.error(f"Unexpected error: {e}", exc_info=True)
        return {
            "success": False,
            "error": "Internal error",
            "error_type": type(e).__name__
        }
```

---

## 5. Introspection and Discovery Features

### 5.1 Automatic Tool Discovery

**BaseAdapter provides automatic introspection:**

```python
# From base_adapter.py
def get_tools(self) -> List[ToolRegistration]:
    """Discover and return tool specifications for all tools."""
    if self._tools_cache is not None:
        return self._tools_cache

    tools = []

    # Discover all methods marked with @tool decorator
    for name, method in inspect.getmembers(self, inspect.ismethod):
        if hasattr(method, '_tool_metadata'):
            tool_reg = self._create_tool_registration(name, method)
            tools.append(tool_reg)

    self._tools_cache = tools
    return tools
```

**Key Features:**
1. **Decorator-based discovery** - Only methods with `@tool` are exposed
2. **Caching** - Tool list is computed once and cached
3. **Metadata extraction** - Parameters, types, defaults all automatic
4. **Zero boilerplate** - Just add `@tool` to your methods

### 5.2 Parameter Introspection

**Automatic parameter extraction from function signatures:**

```python
def _create_parameter_spec(self, name: str, param: inspect.Parameter):
    # Extract type from annotation
    param_type = 'any'
    if param.annotation != inspect.Parameter.empty:
        type_name = getattr(param.annotation, '__name__', str(param.annotation))
        param_type = type_name.lower()

    # Check if required (no default value)
    required = param.default == inspect.Parameter.empty

    return ParameterSpec(
        name=name,
        type=param_type,
        required=required,
        default_value=json.dumps(param.default) if not required else None
    )
```

**Example:**
```python
@tool(description="Example with introspection")
def example_tool(self,
                 required_str: str,
                 optional_int: int = 42,
                 optional_list: list = None) -> dict:
    pass

# Generates:
# ParameterSpec(name="required_str", type="str", required=True)
# ParameterSpec(name="optional_int", type="int", required=False, default=42)
# ParameterSpec(name="optional_list", type="list", required=False, default=None)
```

### 5.3 Elixir Tool Discovery (Bidirectional)

**Python can discover available Elixir tools:**

```python
# From session_context.py
@property
def elixir_tools(self) -> Dict[str, Any]:
    """Lazy-load available Elixir tools."""
    if self._elixir_tools is None:
        self._elixir_tools = self._load_elixir_tools()
    return self._elixir_tools

def _load_elixir_tools(self) -> Dict[str, Any]:
    """Load exposed Elixir tools via gRPC."""
    request = GetExposedElixirToolsRequest(session_id=self.session_id)
    response = self.stub.GetExposedElixirTools(request)

    tools = {}
    for tool_spec in response.tools:
        tools[tool_spec.name] = {
            'name': tool_spec.name,
            'description': tool_spec.description,
            'parameters': dict(tool_spec.parameters)
        }

    return tools
```

**Usage:**
```python
# Discover tools
ctx = SessionContext(stub, session_id)
available_tools = ctx.elixir_tools
# => {'parse_json': {...}, 'calculate_fibonacci': {...}, ...}

# Tool proxy pattern
parse_json = ctx.elixir_tools["parse_json"]
result = parse_json(json_string='{"test": true}')
```

### 5.4 Runtime Tool Registration

**Python adapters register tools with Elixir at runtime:**

```python
# From base_adapter.py
def register_with_session(self, session_id: str, stub) -> List[str]:
    """Register adapter tools with the Elixir session."""
    tools = self.get_tools()  # Auto-discovered via @tool decorators

    request = RegisterToolsRequest(
        session_id=session_id,
        tools=tools,
        worker_id=f"python-{id(self)}"
    )

    response = stub.RegisterTools(request)
    if response.success:
        return list(response.tool_ids.keys())
    else:
        logger.error(f"Failed to register tools: {response.error_message}")
        return []
```

**Async variant for asyncio-based adapters:**
```python
async def register_with_session_async(self, session_id: str, stub):
    """Non-blocking registration for async adapters."""
    tools = self.get_tools()
    request = RegisterToolsRequest(session_id=session_id, tools=tools)

    raw_response = stub.RegisterTools(request)
    response = await self._await_stub_response(raw_response)

    return list(response.tool_ids.keys()) if response.success else []
```

---

## 6. Test Patterns and Real Usage

### 6.1 Python Unit Tests

**From `test_base_adapter.py`:**
```python
import pytest
from snakepit_bridge.base_adapter import BaseAdapter, tool

class SampleAdapter(BaseAdapter):
    @tool(description="Echo back text")
    def echo(self, text: str) -> str:
        return text

@pytest.mark.asyncio
async def test_register_with_session_async():
    adapter = SampleAdapter()
    result = await adapter.register_with_session_async("session-1", mock_stub)
    assert "echo" in result
```

**Key Test Patterns:**
- Use `pytest` with `@pytest.mark.asyncio` for async tests
- Mock gRPC stubs for unit testing
- Test both sync and async registration paths
- Verify parameter introspection works correctly

### 6.2 Elixir Integration Tests

**From `test/snakepit/grpc/bridge_server_test.exs`:**
```elixir
test "execute_tool with binary parameters", %{session_id: session_id} do
  # Register Elixir tool
  ToolRegistry.register_elixir_tool(session_id, "binary_tool", fn params ->
    # Verify binary data received correctly
    assert params["blob"] == {:binary, expected_binary}
    {:ok, :ok}
  end)

  # Execute with binary parameters
  binary_payload = :erlang.term_to_binary(%{payload: "opaque"})

  request = %ExecuteToolRequest{
    session_id: session_id,
    tool_name: "binary_tool",
    parameters: %{"count" => encode_json(1)},
    binary_parameters: %{"blob" => binary_payload}
  }

  response = BridgeServer.execute_tool(request, nil)
  assert %ExecuteToolResponse{success: true} = response
end
```

**Test Patterns:**
- Session isolation via unique session IDs
- Binary parameter handling
- Error case testing (malformed JSON, missing tools)
- Channel reuse verification
- Worker affinity checks

### 6.3 End-to-End Examples

**From the showcase tests:**
```elixir
# Start pool
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :pool_config, %{pool_size: 4})
{:ok, _} = Application.ensure_all_started(:snakepit)

# Create session
session_id = "demo_session_#{:os.system_time(:millisecond)}"
{:ok, _session} = SessionStore.create_session(session_id)

# Execute Python tool
{:ok, result} = Snakepit.execute_in_session(
  session_id,
  "ml_analyze_text",
  %{text: "Sample text for analysis"}
)

# Stream progress
Snakepit.execute_in_session_stream(
  session_id,
  "stream_progress",
  %{steps: 10, delay_ms: 100},
  fn chunk ->
    IO.puts("Progress: #{chunk["progress"]}%")
  end
)
```

---

## 7. Lessons for Snakebridge v2 Design

### 7.1 What Works Extremely Well

**1. Decorator-Based Tool Discovery**
- ✅ Zero boilerplate - just add `@tool(description="...")`
- ✅ Automatic parameter introspection from type hints
- ✅ Clear, pythonic API
- ✅ Easy to understand and teach

**Recommendation:** Adopt this pattern for snakebridge v2

**2. Stateless Python / Stateful Elixir**
- ✅ Workers can be recycled without data loss
- ✅ Elixir owns session state via SessionStore
- ✅ Clean separation of concerns
- ✅ Scales horizontally

**Recommendation:** Keep this architecture principle

**3. Bidirectional Tool Bridge**
- ✅ Python can call Elixir tools seamlessly
- ✅ Tool proxies feel like native functions
- ✅ Enables hybrid workflows
- ✅ Auto-discovery of available tools

**Recommendation:** Essential feature for v2

**4. Handler Pattern for Large Adapters**
- ✅ Clear domain separation
- ✅ Easier to test individual handlers
- ✅ Better code organization
- ✅ Reusable handler logic

**Recommendation:** Document this pattern prominently

**5. Streaming Support**
- ✅ First-class, not bolted on
- ✅ Clean chunk envelope (`is_final`, metadata)
- ✅ Works with gRPC HTTP/2 streaming
- ✅ Progress updates are natural

**Recommendation:** Must-have for v2

### 7.2 What Could Be Improved

**1. Manifest Generation**
- ❌ Currently no tooling to auto-generate manifests from Python code
- ❌ Developers must manually maintain JSON manifests
- ❌ Risk of drift between code and manifest

**Recommendation for v2:**
- Build a `mix snakebridge.gen.manifest` task
- Auto-generate manifests from `@tool` decorators
- Include: parameter specs, types, defaults, streaming support
- Support manifest validation/linting

**2. Type System**
- ⚠️ Type introspection is basic (`str`, `int`, `float`, `any`)
- ⚠️ No support for complex types (Union, Optional, List[str], etc.)
- ⚠️ No runtime type validation

**Recommendation for v2:**
- Leverage Python's `typing` module more deeply
- Support: `Optional[T]`, `List[T]`, `Dict[K,V]`, `Union[T1,T2]`
- Consider using `pydantic` for runtime validation
- Generate TypeSpec from Python type hints

**3. Documentation Generation**
- ❌ No automatic doc generation from adapters
- ❌ Parameter docs must be manually written
- ❌ No way to list all tools in a system

**Recommendation for v2:**
- Auto-generate docs from docstrings + `@tool` metadata
- Support `mix snakebridge.docs` command
- Generate Markdown/HTML reference docs
- Include examples from docstrings

**4. Adapter Versioning**
- ⚠️ No built-in versioning strategy
- ⚠️ Breaking changes hard to detect
- ⚠️ No migration path documented

**Recommendation for v2:**
- Include version in adapter metadata
- Support semantic versioning
- Detect breaking changes (removed tools, changed params)
- Provide migration guides

**5. Testing Utilities**
- ⚠️ Limited test helpers for adapter developers
- ⚠️ Need to mock gRPC stubs manually
- ⚠️ No fixture generators

**Recommendation for v2:**
- Provide `Snakebridge.TestHelpers` module
- Mock gRPC stubs automatically
- Generate test fixtures from manifests
- Support property-based testing

### 7.3 Critical Patterns to Preserve

**1. SessionContext Pattern**
```python
# Always available via self.session_context
session_id = self.session_context.session_id
elixir_result = self.session_context.call_elixir_tool('tool_name', **kwargs)
```

**2. Lazy Tool Discovery**
```python
# Tools discovered once and cached
tools = adapter.get_tools()  # Cached after first call
```

**3. Sync + Async Registration**
```python
# Support both sync and async adapters
registered = adapter.register_with_session(session_id, stub)
registered = await adapter.register_with_session_async(session_id, stub)
```

**4. Binary Data Handling**
```elixir
# Separate binary_parameters map
Snakepit.execute("tool", %{...}, binary_parameters: %{"data" => binary})
```

**5. Streaming Chunk Envelope**
```python
yield StreamChunk(
    data={...},
    is_final=True/False
)
```

### 7.4 New Capabilities for v2

Based on snakepit's maturity, snakebridge v2 should add:

**1. Manifest-First Development**
- Generate Python code from manifests
- Generate Elixir code from manifests
- Validate implementations against manifests

**2. Multi-Language Support**
- Snakepit is Python-only
- v2 should support: Node.js, Ruby, Go, Rust
- Use protobuf as common format

**3. Local Development Mode**
- Snakepit requires full pool setup
- v2 should support "dev mode" with single worker
- Hot reload for rapid iteration

**4. Better Error Messages**
- Include parameter validation errors
- Show expected vs actual types
- Suggest similar tool names on typos

**5. Performance Metrics**
- Tool execution timing
- Memory usage per tool
- Cache hit rates
- Queue depths

---

## 8. Complete Adapter Template

Based on research, here's the recommended adapter structure for snakebridge v2:

```python
"""
MyAdapter - Example adapter for Snakebridge v2

This adapter demonstrates best practices:
- Decorator-based tool discovery
- Handler organization for complex domains
- Proper error handling
- Streaming support
- Telemetry integration
- Bidirectional tool calls
"""

from typing import Dict, Any, List, Optional
from snakebridge.base_adapter import BaseAdapter, tool
from snakebridge import telemetry
from snakebridge.adapters.showcase.tool import StreamChunk

# Optional: organize into handlers for large adapters
from .handlers import DataHandler, MLHandler


class MyAdapter(BaseAdapter):
    """
    Adapter for [describe your domain].

    Capabilities:
    - [List key capabilities]

    Configuration:
    - Required environment variables: [list]
    - Optional settings: [list]
    """

    def __init__(self, config: Optional[Dict[str, Any]] = None):
        super().__init__()
        self.config = config or {}
        self.session_context = None  # Set by framework

        # Optional: initialize handlers
        self.handlers = {
            'data': DataHandler(self.config),
            'ml': MLHandler(self.config)
        }

    # Basic Operations

    @tool(description="Health check endpoint")
    def ping(self) -> Dict[str, str]:
        """Simple health check."""
        return {
            "status": "healthy",
            "adapter": "MyAdapter",
            "version": "1.0.0"
        }

    @tool(description="Get adapter information")
    def adapter_info(self) -> Dict[str, Any]:
        """Return adapter capabilities and configuration."""
        return {
            "name": "MyAdapter",
            "version": "1.0.0",
            "capabilities": [
                "data_processing",
                "ml_inference",
                "streaming",
                "binary_data"
            ],
            "handlers": list(self.handlers.keys())
        }

    # Data Processing

    @tool(description="Process data with configurable operations")
    def process_data(self,
                     data: Dict[str, Any],
                     operation: str = "transform",
                     options: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Process data using various operations.

        Args:
            data: Input data to process
            operation: Operation to perform (transform, validate, clean)
            options: Operation-specific options

        Returns:
            Processed data with metadata

        Example:
            result = adapter.process_data(
                data={"values": [1, 2, 3]},
                operation="transform",
                options={"method": "normalize"}
            )
        """
        try:
            # Delegate to handler
            result = self.handlers['data'].process(data, operation, options)

            return {
                "success": True,
                "operation": operation,
                "result": result,
                "metadata": {
                    "session_id": self.session_context.session_id,
                    "timestamp": time.time()
                }
            }
        except ValueError as e:
            return {
                "success": False,
                "error": "Invalid input",
                "details": str(e)
            }

    # Streaming Operations

    @tool(description="Stream processing results", supports_streaming=True)
    def process_stream(self,
                       items: List[Any],
                       batch_size: int = 10,
                       delay_ms: int = 100):
        """
        Process items and stream results as they complete.

        Yields StreamChunks with progress updates.
        """
        total = len(items)
        processed = 0

        for i in range(0, total, batch_size):
            batch = items[i:i + batch_size]
            batch_result = self._process_batch(batch)
            processed += len(batch)

            yield StreamChunk(
                data={
                    "batch_index": i // batch_size,
                    "processed": processed,
                    "total": total,
                    "progress": processed / total * 100,
                    "batch_result": batch_result
                },
                is_final=(processed >= total)
            )

            if processed < total:
                time.sleep(delay_ms / 1000.0)

    # Binary Data

    @tool(description="Process binary data (images, files, etc.)")
    def process_binary(self,
                      data: bytes,
                      format: str = "auto",
                      operation: str = "analyze") -> Dict[str, Any]:
        """
        Process binary data like images or files.

        Args:
            data: Binary data
            format: Data format (auto, image, pdf, binary)
            operation: Operation to perform

        Returns:
            Processing results with metadata
        """
        import hashlib

        return {
            "size_bytes": len(data),
            "checksum": hashlib.md5(data).hexdigest(),
            "format": format,
            "operation": operation,
            "result": self._process_binary_data(data, format, operation)
        }

    # Hybrid Processing (Python + Elixir)

    @tool(description="Hybrid processing using both Python and Elixir")
    def hybrid_process(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Demonstrate calling Elixir tools from Python.

        This allows leveraging Elixir's strengths (pattern matching,
        concurrency, data validation) from Python tools.
        """
        # Python processing
        python_result = self._local_processing(data)

        # Call Elixir for validation
        try:
            elixir_result = self.session_context.call_elixir_tool(
                'validate_schema',
                schema=python_result
            )

            return {
                "python_processing": python_result,
                "elixir_validation": elixir_result,
                "combined": True
            }
        except Exception as e:
            return {
                "python_processing": python_result,
                "elixir_error": str(e),
                "combined": False
            }

    # Telemetry Integration

    @tool(description="Operation with telemetry tracking")
    def tracked_operation(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Example of telemetry integration."""
        correlation_id = telemetry.get_correlation_id()

        # Emit start event
        telemetry.emit(
            "operation.start",
            {"timestamp": time.time_ns()},
            {"operation": "tracked_operation"},
            correlation_id=correlation_id
        )

        # Use span for automatic timing
        with telemetry.span("operation", {"data_size": len(data)}, correlation_id):
            result = self._do_work(data)

            # Emit custom metric
            telemetry.emit(
                "operation.result_size",
                {"bytes": len(str(result))},
                {"operation": "tracked_operation"},
                correlation_id=correlation_id
            )

        return result

    # Private helpers

    def _process_batch(self, batch: List[Any]) -> List[Any]:
        """Process a batch of items."""
        return [self._process_item(item) for item in batch]

    def _process_item(self, item: Any) -> Any:
        """Process a single item."""
        # Implementation details
        pass

    def _process_binary_data(self, data: bytes, format: str, operation: str) -> Any:
        """Process binary data."""
        # Implementation details
        pass

    def _local_processing(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Local Python processing."""
        # Implementation details
        pass

    def _do_work(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Perform work with telemetry."""
        # Implementation details
        pass
```

---

## 9. Key Architecture Decisions

### 9.1 Why gRPC?

**Chosen over stdin/stdout because:**
1. **HTTP/2 multiplexing** - Multiple concurrent requests over one connection
2. **Native streaming** - Bidirectional streaming built-in
3. **Binary efficiency** - Protobuf is more efficient than JSON
4. **Type safety** - Schema-first development
5. **Better error handling** - Rich status codes and metadata

### 9.2 Why Stateless Python?

**Design rationale:**
1. **Worker recycling** - Can restart Python workers without data loss
2. **Horizontal scaling** - Any worker can handle any request
3. **Fault tolerance** - Crashed worker doesn't lose session state
4. **Memory management** - Easier to detect and fix memory leaks
5. **Testing** - Easier to test stateless functions

### 9.3 Why Decorator Pattern?

**Benefits:**
1. **Zero boilerplate** - Just `@tool(description="...")`
2. **Pythonic** - Feels natural to Python developers
3. **Introspectable** - Can discover tools automatically
4. **Metadata-rich** - Description, parameters, streaming support all in one place
5. **Composable** - Can stack decorators for cross-cutting concerns

---

## 10. References

### Key Files Studied

**Python Side:**
- `/home/home/p/g/n/snakepit/priv/python/snakepit_bridge/base_adapter.py`
- `/home/home/p/g/n/snakepit/priv/python/snakepit_bridge/session_context.py`
- `/home/home/p/g/n/snakepit/priv/python/snakepit_bridge/adapters/showcase/showcase_adapter.py`
- `/home/home/p/g/n/snakepit/priv/python/grpc_server.py`

**Elixir Side:**
- `/home/home/p/g/n/snakepit/lib/snakepit/bridge/session_store.ex`
- `/home/home/p/g/n/snakepit/lib/snakepit/bridge/tool_registry.ex`
- `/home/home/p/g/n/snakepit/lib/snakepit/grpc/bridge_server.ex`

**Examples:**
- `/home/home/p/g/n/snakepit/examples/grpc_basic.exs`
- `/home/home/p/g/n/snakepit/examples/grpc_sessions.exs`
- `/home/home/p/g/n/snakepit/examples/grpc_streaming.exs`
- `/home/home/p/g/n/snakepit/examples/bidirectional_tools_demo.exs`
- `/home/home/p/g/n/snakepit/examples/python_elixir_tools_demo.py`

**Documentation:**
- `/home/home/p/g/n/snakepit/README.md` (32,465 tokens - extensive!)
- `/home/home/p/g/n/snakepit/README_GRPC.md`
- `/home/home/p/g/n/snakepit/ARCHITECTURE.md`

**Tests:**
- `/home/home/p/g/n/snakepit/priv/python/tests/test_base_adapter.py`
- `/home/home/p/g/n/snakepit/test/snakepit/grpc/bridge_server_test.exs`

---

## Conclusion

Snakepit provides an excellent reference implementation for snakebridge v2. The key patterns to adopt:

1. **Decorator-based tool discovery** - Clean, pythonic, zero boilerplate
2. **Stateless workers** - Elixir owns state, Python is disposable
3. **Bidirectional bridge** - Seamless cross-language tool calls
4. **Handler pattern** - Organize large adapters by domain
5. **Streaming first** - Not an afterthought
6. **gRPC protocol** - Modern, efficient, streaming-native
7. **Automatic introspection** - From type hints to parameter specs

Snakebridge v2 should build on these foundations while adding:
- Manifest auto-generation from code
- Better type system support
- Documentation generation
- Multi-language support beyond Python
- Improved developer experience (hot reload, better errors)

The research shows that snakepit's architecture is battle-tested and production-ready. Snakebridge v2 should evolve these patterns rather than reinvent them.
