# Phase 1C: Cross-Ecosystem Analysis of Python Adapters

**Document Version**: 1.0
**Date**: November 26, 2025
**Author**: AI Research Analysis for SnakeBridge
**Purpose**: Extract design patterns from mature cross-language Python integration projects

---

## Executive Summary

This document analyzes seven mature cross-language Python integration projects to extract architectural patterns, anti-patterns, and design lessons for SnakeBridge's plugin architecture. The goal is to synthesize decades of cross-language integration experience into concrete recommendations for making SnakeBridge adapters as elegant as PyO3, as mature as JPype, and as performant as Apache Arrow.

### Key Findings

1. **Type Conversion is the Core Challenge** - All successful projects invest heavily in sophisticated, extensible type conversion systems
2. **Trait/Protocol-Based Extensibility Wins** - PyO3's trait system and JPype's customizer pattern enable elegant user extensions
3. **Memory Management Must Be Explicit** - Lifecycle, ownership, and GC coordination require careful architectural design
4. **Async Requires Separate Event Loops** - Attempting to merge async runtimes is complex; separate loops with bridges work better
5. **Zero-Copy via Shared Standards** - Apache Arrow demonstrates that standardized memory layouts enable true zero-copy
6. **Error Handling is Non-Negotiable** - Exception propagation must be transparent and preserve context across boundaries
7. **Developer Experience Through Conventions** - Smart defaults, derive macros, and familiar patterns reduce cognitive load

---

## 1. PyO3 (Rust ↔ Python)

**Project**: [PyO3/pyo3](https://github.com/PyO3/pyo3)
**Maturity**: Production (Rust 1.83+)
**Architecture**: Native C extension using Python/C API

### Core Architecture

PyO3 provides three architectural layers:
1. **Low-level Python/C API bindings** (`JP` namespace in C++)
2. **Safe object wrappers** (`Bound<'py, T>`, `Py<T>`, `Borrowed<'a, 'py, T>`)
3. **High-level trait system** (`FromPyObject`, `IntoPyObject`, `PyClass`)

The design philosophy: "Make Python objects feel Rustic while maintaining Python's object model."

### Type System: Trait-Based Bidirectional Conversion

PyO3's genius is its **trait-based extensibility**:

```rust
// Core conversion traits
pub trait FromPyObject<'source>: Sized {
    fn extract(ob: &'source PyAny) -> PyResult<Self>;
}

pub trait IntoPyObject: Sized {
    fn into_pyobject(self, py: Python<'_>) -> PyResult<Bound<'_, PyAny>>;
}
```

**Key Features:**

1. **Derive Macros for Zero-Boilerplate**:
   ```rust
   #[derive(FromPyObject)]
   struct Config {
       #[pyo3(attribute)]        // Extract from Python attribute (default)
       name: String,

       #[pyo3(item("max_iter"))] // Extract from dict key
       iterations: usize,

       #[pyo3(from_py_with = "custom_converter")]
       model: ModelType,
   }
   ```

2. **Match Levels for Overload Resolution**:
   - **Exact (X)**: Type matches perfectly (prioritized)
   - **Implicit (I)**: Automatic conversion possible
   - **Explicit (E)**: Requires wrapper cast
   - Similar to JPype's tiered conversion system

3. **Smart Pointer Abstraction**:
   - `Bound<'py, T>`: Owned reference with GIL lifetime
   - `Borrowed<'a, 'py, T>`: Non-owning reference (optimized refcounting)
   - `Py<T>`: Owned reference without GIL lifetime
   - Unified via `BoundObject` trait for generic handling

### Memory Management

**Lifetime-Based Safety**: Rust's borrow checker enforces Python GIL requirements at compile time.

```rust
fn process(py: Python<'_>) -> PyResult<()> {
    let list: Bound<'_, PyList> = PyList::new_bound(py, &[1, 2, 3]);
    // 'py lifetime ensures GIL is held while list is accessible
    Ok(())
}
// GIL released here, list becomes inaccessible
```

**Lesson for SnakeBridge**: Elixir's process model differs from Rust's, but we can use **reference counting** in adapters to track Python object lifetimes across the gRPC boundary.

### Extensibility Pattern

Users extend PyO3 by:
1. Implementing `FromPyObject` and `IntoPyObject` for custom types
2. Using `#[pyo3(from_py_with = "function")]` for field-level customization
3. Defining `#[pyclass]` types that become native Python classes in Rust

**Code Example**:
```rust
// Custom conversion for a domain type
impl<'source> FromPyObject<'source> for Timestamp {
    fn extract(ob: &'source PyAny) -> PyResult<Self> {
        let unix: i64 = ob.extract()?;
        Ok(Timestamp::from_unix(unix))
    }
}
```

### Performance Considerations

- **Zero-cost abstractions**: Traits compile to direct function calls
- **Opt-in copying**: `PyArray` wraps NumPy without copying; `.extract()` copies
- **Type check overhead**: Python native types (minimal check) vs. Rust types (conversion cost)

**Metrics**: "Once the conversion cost is paid, Rust code runs at native speed free of Python's runtime."

### Error Handling

PyO3 maps Rust's `Result<T, E>` to Python exceptions:
```rust
#[pyfunction]
fn divide(a: f64, b: f64) -> PyResult<f64> {
    if b == 0.0 {
        Err(PyValueError::new_err("division by zero"))
    } else {
        Ok(a / b)
    }
}
```

**Exception propagation**: If a Rust function returns `Err`, PyO3 sets the Python exception indicator without immediately unwinding. The C API caller checks the return value and propagates.

### Lessons for SnakeBridge

✅ **Adopt**: Trait-based type conversion with derive macros
✅ **Adopt**: Tiered conversion matching (exact/implicit/explicit)
✅ **Adopt**: Smart pointer abstraction for different ownership scenarios
✅ **Adapt**: Field-level conversion customization (`from_py_with` equivalent)
⚠️ **Avoid**: Rust's borrow checker doesn't map to Elixir; use process-based isolation instead

**Proposed SnakeBridge Pattern**:
```elixir
defmodule SnakeBridge.TypeConverter do
  @callback from_python(term()) :: {:ok, term()} | {:error, term()}
  @callback to_python(term()) :: {:ok, term()} | {:error, term()}
end

# User-defined converter
defmodule MyApp.TimestampConverter do
  @behaviour SnakeBridge.TypeConverter

  def from_python(unix_timestamp) when is_integer(unix_timestamp) do
    {:ok, DateTime.from_unix!(unix_timestamp)}
  end

  def to_python(%DateTime{} = dt) do
    {:ok, DateTime.to_unix(dt)}
  end
end
```

---

## 2. pyo3-asyncio (Async Rust ↔ Python)

**Project**: [PyO3/pyo3-async-runtimes](https://github.com/PyO3/pyo3-async-runtimes)
**Status**: Successor to pyo3-asyncio for PyO3 0.21+
**Challenge**: Bridge two incompatible async runtimes

### Core Insight: Separate Event Loops

**Design Decision**: Run Rust async runtimes (tokio, async-std) in background threads while surrendering the main thread to Python's asyncio.

**Rationale**:
- Python's signal handling requires main thread control
- Rust runtimes are flexible and thread-agnostic
- Attempting to merge event loops is unnecessarily complex

### Bridging Patterns

**1. Future-to-Coroutine Conversion**:
```rust
use pyo3_async_runtimes::tokio::future_into_py;

#[pyfunction]
fn rust_async_function(py: Python) -> PyResult<&PyAny> {
    future_into_py(py, async {
        // Rust async code
        tokio::time::sleep(Duration::from_secs(1)).await;
        Ok("done")
    })
}
```

**2. Coroutine-to-Future Conversion**:
```rust
use pyo3_async_runtimes::tokio::into_future;

async fn call_python_async(coro: &PyAny) -> PyResult<PyObject> {
    into_future(coro).await
}
```

### Context Propagation: TaskLocals Pattern

**Problem**: Rust threads aren't associated with Python event loops, so `asyncio.get_running_loop()` fails.

**Solution**: `TaskLocals` structure passes event loop + context explicitly:
```rust
pub struct TaskLocals {
    event_loop: PyObject,
    context: Option<PyObject>,
}
```

**Lesson**: Cross-language async requires **explicit context threading**.

### Streaming Support

pyo3-asyncio supports Python async generators → Rust `Stream` conversion (experimental in v0.16).

### Lessons for SnakeBridge

✅ **Adopt**: Separate event loops with explicit bridging
✅ **Adopt**: TaskLocals pattern for context propagation
✅ **Adopt**: Bidirectional async conversion (Elixir Stream ↔ Python AsyncIterator)
⚠️ **Avoid**: Don't try to merge BEAM scheduler with Python asyncio

**Proposed SnakeBridge Pattern**:
```elixir
defmodule SnakeBridge.Async do
  # Convert Python async generator to Elixir Stream
  def from_python_async_gen(session_id, generator_ref) do
    Stream.resource(
      fn -> {session_id, generator_ref} end,
      fn {session_id, gen_ref} ->
        case SnakeBridge.Runtime.execute_stream(session_id, gen_ref, %{}) do
          {:ok, chunk} -> {[chunk], {session_id, gen_ref}}
          {:done, _} -> {:halt, {session_id, gen_ref}}
        end
      end,
      fn {session_id, _gen_ref} -> :ok end
    )
  end
end
```

---

## 3. JPype (Java ↔ Python)

**Project**: [jpype-project/jpype](https://github.com/jpype-project/jpype)
**Maturity**: 20+ years in production
**Architecture**: JNI-based bridge embedding JVM in Python process

### Core Philosophy: "Clarity over Performance"

JPype's 20-year evolution teaches: **Simplicity and consistency trump raw speed.**

Key principle: "Mixing two languages is inherently complex, so JPype minimizes additional complexity by maintaining a simple and consistent design."

### Type Matching: Four-Level Hierarchy

JPype implements sophisticated overload resolution:

| Level | Name | Description |
|-------|------|-------------|
| None | No match | Conversion impossible |
| E | Explicit | Requires `@` cast operator |
| I | Implicit | Automatic conversion |
| X | Exact | Highest priority in dispatch |

**Example**:
```python
# Python int → Java long: Exact match
# Python int → Java byte: Implicit (if value fits)
# Python str → Java String: Implicit
# Python list → Java array: Explicit via JArray.of()
```

### Method Overload Resolution

**Problem**: Python lacks native overloading; Java has it everywhere.

**Solution**: Wrap all Java methods as dispatchers:
1. Collect all methods with matching name from class hierarchy
2. Rank candidates using conversion match table
3. Select best candidate or raise `TypeError` if ambiguous

**Optimization**: Cache resolution results to avoid re-evaluation.

**Lesson**: Overload resolution is expensive; caching is essential.

### Customizer Pattern (Extensibility)

JPype applies specialized behavior through **wrapper classes**:

- **Boxed types** inherit from Python `int`/`float` for seamless arithmetic
- **String class** implements `__len__`, `__getitem__`, `__contains__`
- **Array classes** support slicing, buffer protocol, iteration
- **Exception classes** derive from Python exceptions where applicable

**Historical Lesson**: "The property conversion customizer was deactivated by default because it proved very problematic. It overrode certain customizers, hid intentionally exposed fields, bloated dictionary tables, and interfered with exception unwrapping."

**Takeaway**: Customizers must be **opt-in, not opt-out**, with clear precedence rules.

### Proxy Pattern (Python → Java Callbacks)

Enable Python classes to implement Java interfaces:

```python
from jpype import JImplements, JOverride

@JImplements(Monitor)
class HeartMonitor:
    @JOverride
    def onMeasurement(self, measurement):
        self.readings.append([measurement.getTime(),
                             measurement.getHeartRate()])

monitor = HeartMonitor()
device.setMonitor(monitor)  # Java sees a Monitor interface
```

**Validation**: `@JImplements` decorator validates all required methods are present at decoration time.

### Performance: Buffer Transfer Optimization

For high-performance scenarios, JPype exposes direct memory access:

```python
buffer = memoryview(jint_array)
numpy_array = np.array(buffer)  # Zero-copy for primitives
```

**Architecture**: Both VMs share the same process memory space, enabling shared buffers.

### Lessons for SnakeBridge

✅ **Adopt**: Four-level type matching with caching
✅ **Adopt**: Customizer pattern for type-specific behavior
✅ **Adopt**: Proxy pattern for bidirectional callbacks
✅ **Adopt**: Buffer protocol for zero-copy data transfer
⚠️ **Avoid**: Automatic customizers (opt-in only)
⚠️ **Avoid**: Overriding user-exposed fields with convenience methods

**Proposed SnakeBridge Pattern**:
```elixir
defmodule SnakeBridge.Customizer do
  @callback customize(module_ast :: Macro.t()) :: Macro.t()
end

defmodule SnakeBridge.Customizers.DataFrame do
  @behaviour SnakeBridge.Customizer

  def customize(ast) do
    # Add Elixir-friendly methods to Pandas DataFrames
    quote do
      unquote(ast)

      def to_map(instance) do
        # Convert DataFrame to Elixir map
      end

      def stream_rows(instance) do
        # Return Stream of rows
      end
    end
  end
end
```

---

## 4. PyCall.jl (Julia ↔ Python)

**Project**: [JuliaPy/PyCall.jl](https://github.com/JuliaPy/PyCall.jl)
**Architecture**: Python C API embedding Python in Julia process
**Successor**: PythonCall.jl (improved design)

### Core Insight: Zero-Copy for Compatible Types

**NumPy Array Handling**:
- Julia `Array` → NumPy: **Zero-copy** (NumPy wraps Julia memory)
- NumPy → Julia: **Copy** (column-major compatibility)

**Memory Layout**: Both Julia and NumPy support column-major (Fortran-style) arrays, enabling shared memory.

**Code**:
```julia
# Zero-copy Julia → Python
a = [1, 2, 3, 4, 5]
py_array = PyObject(a)  # NumPy wraps Julia's memory

# Copy Python → Julia (to ensure column-major)
julia_array = convert(Array, py_array)
```

### PyArray: No-Copy Wrapper

**Pattern**: `PyArray` type subclasses `AbstractArray` and implements Julia's array interface while wrapping NumPy memory:

```julia
# No-copy wrapper
arr = PyArray(numpy_array)
arr[1]  # Accesses NumPy memory directly
```

**Limitation**: Currently only for numeric types and objects, not all Python types.

### PyReverseDims: Row-Major Compatibility

**Problem**: NumPy defaults to row-major (C-style); Julia is column-major.

**Solution**: `PyReverseDims(a)` passes Julia array as row-major NumPy array with dimensions reversed:

```julia
# Julia array (3, 4) → NumPy array (4, 3) row-major
PyReverseDims(julia_array)
```

**Lesson**: Different memory layouts require **explicit user control**, not automatic conversion.

### Object Lifetime Management

**Critical Rule**: "You must not access any Python functions or data after `pyfinalize()` runs!"

**Design**: PyCall uses Python's reference counting. Julia's GC finalizers decrement Python refcounts.

**PythonCall.jl Improvement**: "By default never copies mutable objects when converting, but instead directly wraps them. This means modifying the converted object modifies the original."

### Lessons for SnakeBridge

✅ **Adopt**: Zero-copy for compatible memory layouts (via Arrow)
✅ **Adopt**: Explicit control over memory layout (row-major vs. column-major)
✅ **Adopt**: Wrapper types for no-copy access
⚠️ **Avoid**: Automatic copying (make it explicit to users)
⚠️ **Avoid**: Accessing Python objects after session shutdown

**Proposed SnakeBridge Pattern**:
```elixir
defmodule SnakeBridge.ZeroCopy do
  # Use Apache Arrow for zero-copy transfer
  def transfer_dataframe(session_id, df_ref) do
    # Python writes DataFrame to Arrow IPC buffer
    # Elixir reads via Arrow C Data Interface
    # No serialization, no copy
  end
end
```

---

## 5. reticulate (R ↔ Python)

**Project**: [rstudio/reticulate](https://rstudio.github.io/reticulate/)
**Architecture**: Embedded Python session within R session
**Unique Feature**: Bidirectional notebook integration (R Markdown)

### Core Architecture: Persistent Python Session

**Design**: Embed a single Python interpreter inside the R process, maintaining shared state across calls.

**Benefit**: "Run Python chunks in a single Python session embedded within your R session (shared variables/state between Python chunks)."

### Object Access Pattern: Symmetric `py` and `r` Objects

**R → Python**:
```r
# Access Python object from R
py$x
```

**Python → R**:
```python
# Access R object from Python
r.x
```

**Lesson**: **Symmetric syntax** reduces cognitive load when switching languages.

### Type Conversion: DataFrame Impedance Mismatch

**Problem**: Pandas DataFrame ≠ R data.frame (different internal structures).

**Solution**: **Copy and convert** when crossing boundary:
- R data.frame → Pandas DataFrame (via conversion)
- Pandas DataFrame → R data.frame (via conversion)

**Limitation**: "It's not possible for the two languages to share a single copy of the same data object because they don't agree on what constitutes 'a data object'."

### Apache Arrow Integration: Zero-Copy Revolution

**Insight**: Arrow Tables have the **same in-memory structure** in R and Python.

**Benefit**: "If your data are stored as an Arrow Table, only the metadata changes hands. The data set itself does not need to be touched at all."

**Performance**: Transfers only **pointer + metadata**, not the data itself.

**Code**:
```r
# R creates Arrow Table
arrow_table <- arrow::as_arrow_table(iris)

# Python receives zero-copy reference
py$arrow_table  # No data copied!
```

### Environment Management: Multiple Python Strategies

reticulate supports:
- Default isolated venv (`r-reticulate`)
- Custom Python via `use_python()`
- Virtual environments via `use_virtualenv()`
- Conda environments via `use_condaenv()`

**Lesson**: **Flexible environment management** is critical for real-world Python integration.

### Lessons for SnakeBridge

✅ **Adopt**: Persistent Python session with shared state
✅ **Adopt**: Symmetric accessor syntax (SnakeBridge.Python.x / Python.R.x)
✅ **Adopt**: Apache Arrow for zero-copy DataFrame transfer
✅ **Adopt**: Flexible Python environment configuration
⚠️ **Avoid**: Pretending incompatible types can share memory

**Proposed SnakeBridge Pattern**:
```elixir
# Symmetric object access
defmodule SnakeBridge.Session do
  def get_python(session_id, var_name) do
    # Access Python variable from Elixir
  end

  def set_elixir(session_id, var_name, value) do
    # Expose Elixir value to Python
  end
end
```

---

## 6. Apache Arrow (Cross-Language Data)

**Project**: [apache/arrow](https://github.com/apache/arrow)
**Purpose**: Universal columnar format for zero-copy data sharing
**Supported Languages**: C, C++, Java, JavaScript, Python, R, Ruby, Rust, Go, Julia

### Core Insight: Standardized Memory Layout Enables Zero-Copy

**Key Principle**: "Arrow is a zero-copy serialization framework. You work on the serialized data itself instead of deserializing first."

**Benefit**: "The bytes your application works on can be transferred over the wire without any modification. On the receiving end, the application can start working on the bytes as-is, without a deserialization step."

### C Data Interface: ABI for In-Process Sharing

**Design**: Two simple C structs (`ArrowSchema`, `ArrowArray`) define the interface:
- **No build dependencies**: Only standard C types
- **No runtime dependencies**: Just function pointers
- **No copying**: Pass memory pointers directly

**Code**:
```c
struct ArrowSchema {
    const char* format;
    const char* name;
    const char* metadata;
    int64_t flags;
    int64_t n_children;
    struct ArrowSchema** children;
    struct ArrowSchema* dictionary;
    void (*release)(struct ArrowSchema*);
};

struct ArrowArray {
    int64_t length;
    int64_t null_count;
    int64_t offset;
    int64_t n_buffers;
    int64_t n_children;
    const void** buffers;
    struct ArrowArray** children;
    struct ArrowArray* dictionary;
    void (*release)(struct ArrowArray*);
};
```

**Lifecycle Management**: `release` callback allows producers to define custom memory management.

### IPC Format: Zero-Copy Across Processes

**Use Cases**:
- Memory-mapped files
- Shared memory between processes
- Network transfer (gRPC, Flight)

**Reading**: "Arrow IPC data is inherently zero-copy if the source allows it (e.g., BufferReader, MemoryMappedFile)."

**Exception**: Compression requires decompression (not zero-copy).

### Performance Benefits

**Claim**: "Moving data between two systems will have no overhead when both use Arrow internally."

**Reality**:
- **Same node**: Shared memory → true zero-copy
- **Network**: Still requires serialization, but format is already in-memory layout

### Lessons for SnakeBridge

✅ **Adopt**: Apache Arrow as primary data interchange format
✅ **Adopt**: C Data Interface for in-process sharing (if Elixir NIFs are used)
✅ **Adopt**: IPC format for gRPC streaming
✅ **Reference**: Use Arrow memory layout for DataFrame/tensor transfer

**Proposed SnakeBridge Integration**:
```elixir
defmodule SnakeBridge.Arrow do
  # Transfer DataFrame via Arrow IPC
  def from_pandas(session_id, df_ref) do
    # Python: df.to_arrow() → IPC buffer
    # gRPC stream: Arrow IPC bytes
    # Elixir: Arrow.Table.from_ipc(bytes)
    # Result: Zero serialization overhead
  end

  def to_pandas(session_id, arrow_table) do
    # Elixir: Arrow.Table.to_ipc(table)
    # gRPC stream: Arrow IPC bytes
    # Python: pa.ipc.open_stream(bytes).read_pandas()
  end
end
```

---

## 7. gRPC Cross-Language Patterns

**Technology**: [gRPC](https://grpc.io/)
**Relevance**: SnakeBridge already uses gRPC; best practices are critical

### Error Handling: Standardized Status Codes

**Official Error Model**: Language-independent status codes + optional details:

| Code | Use Case |
|------|----------|
| `OK` | Success |
| `CANCELLED` | Client cancelled |
| `INVALID_ARGUMENT` | Bad request data |
| `DEADLINE_EXCEEDED` | Timeout |
| `NOT_FOUND` | Resource missing |
| `ALREADY_EXISTS` | Duplicate |
| `PERMISSION_DENIED` | Auth failure |
| `RESOURCE_EXHAUSTED` | Rate limit |
| `INTERNAL` | Server error |
| `UNAVAILABLE` | Service down |

**Python Error Handling**:
```python
try:
    response = stub.Call(request)
except grpc.RpcError as e:
    if e.code() == grpc.StatusCode.INTERNAL:
        print("Internal server error:", e.details())
    elif e.code() == grpc.StatusCode.INVALID_ARGUMENT:
        print("Invalid argument:", e.details())
```

**Lesson**: Use **structured error codes**, not just string messages.

### Streaming Best Practices

**gRPC supports four patterns**:
1. **Unary**: Single request → single response
2. **Server streaming**: Single request → stream of responses
3. **Client streaming**: Stream of requests → single response
4. **Bidirectional streaming**: Both directions stream

**Performance Insight**: "Streaming endpoints perform better than batched unary calls."

**Python Streaming**:
```python
def server_streaming_call(request, context):
    for i in range(10):
        yield Response(value=i)
```

**Backpressure Handling**: gRPC automatically handles flow control; don't implement custom locking.

### Cross-Language Consistency

**Best Practice**: "Ensure method names and error semantics align across languages."

**Anti-Pattern**: Different error codes for the same failure in different language servers.

### Interceptors for Cross-Cutting Concerns

**Pattern**: Use interceptors/middleware for:
- Logging
- Authentication
- Monitoring
- Distributed tracing

**Benefit**: Avoid duplicating logic in every service handler.

### Lessons for SnakeBridge

✅ **Adopt**: Standardized gRPC status codes
✅ **Adopt**: Streaming for data transfer (already doing this)
✅ **Adopt**: Interceptors for telemetry (integrate with `:telemetry`)
✅ **Adopt**: Consistent error semantics across Elixir/Python
⚠️ **Avoid**: Custom backpressure (use gRPC's built-in flow control)

**Current SnakeBridge Status**: Already using gRPC streaming via Snakepit. Need to standardize error codes.

---

## Comparison Matrix

| Feature | PyO3 | JPype | PyCall.jl | reticulate | Arrow | gRPC | SnakeBridge (Current) |
|---------|------|-------|-----------|------------|-------|------|-----------------------|
| **Type Conversion** | Trait-based | 4-level match | Auto + manual | Auto + manual | Columnar only | Protobuf | Config-driven |
| **Extensibility** | Derive macros | Customizers | Manual impls | Limited | N/A | .proto | Manual wrappers |
| **Memory Model** | Lifetime-safe | Shared process | Refcount | Embedded session | Zero-copy | Network copy | gRPC serialize |
| **Async Support** | Separate loops | N/A | N/A | N/A | N/A | Native | Via Snakepit |
| **Error Handling** | Result → Exception | JNI exceptions | PyErr | R errors | Status codes | Status codes | gRPC codes |
| **Zero-Copy** | PyArray wrapper | Buffer protocol | PyArray | Arrow integration | Core feature | No | Not yet |
| **Streaming** | Experimental | N/A | N/A | N/A | IPC format | Core feature | ✅ Implemented |
| **Maturity** | Production | 20+ years | Mature | Production | Production | Production | MVP (v0.2.3) |

---

## Patterns to Adopt

### 1. Trait/Protocol-Based Type Conversion (from PyO3)

**Implementation**:
```elixir
defmodule SnakeBridge.TypeConverter do
  @doc "Convert Python value to Elixir"
  @callback from_python(python_value :: term(), opts :: keyword()) ::
    {:ok, elixir_value :: term()} | {:error, reason :: term()}

  @doc "Convert Elixir value to Python"
  @callback to_python(elixir_value :: term(), opts :: keyword()) ::
    {:ok, python_value :: term()} | {:error, reason :: term()}

  @doc "Match quality for overload resolution"
  @callback match_quality(elixir_value :: term()) :: :exact | :implicit | :explicit | :none
end

# Built-in converters
defmodule SnakeBridge.Converters.Integer do
  @behaviour SnakeBridge.TypeConverter

  def from_python(value, _opts) when is_integer(value), do: {:ok, value}
  def from_python(value, _opts), do: {:error, {:type_mismatch, value}}

  def to_python(value, _opts) when is_integer(value), do: {:ok, value}
  def to_python(value, _opts), do: {:error, {:type_mismatch, value}}

  def match_quality(value) when is_integer(value), do: :exact
  def match_quality(_), do: :none
end

# User-defined converter
defmodule MyApp.DateTimeConverter do
  @behaviour SnakeBridge.TypeConverter

  def from_python(unix_ts, _opts) when is_integer(unix_ts) do
    {:ok, DateTime.from_unix!(unix_ts)}
  end

  def to_python(%DateTime{} = dt, _opts) do
    {:ok, DateTime.to_unix(dt)}
  end

  def match_quality(%DateTime{}), do: :exact
  def match_quality(_), do: :none
end
```

**Config Integration**:
```elixir
config do
  %SnakeBridge.Config{
    converters: [
      # Override default integer conversion
      {:integer, MyApp.CustomIntConverter},

      # Add custom type
      {:datetime, MyApp.DateTimeConverter},

      # Use Arrow for DataFrames
      {:dataframe, SnakeBridge.Converters.ArrowDataFrame}
    ]
  }
end
```

### 2. Customizer Pattern for Generated Modules (from JPype)

**Implementation**:
```elixir
defmodule SnakeBridge.Customizer do
  @doc "Customize generated module AST"
  @callback customize(module_ast :: Macro.t(), context :: map()) :: Macro.t()
end

defmodule SnakeBridge.Customizers.DataFrame do
  @behaviour SnakeBridge.Customizer

  def customize(ast, _context) do
    quote do
      unquote(ast)

      # Add Elixir-friendly methods
      def to_list_of_maps(instance) do
        # Convert Pandas DataFrame to list of Elixir maps
        {:ok, rows} = call_method(instance, "to_dict", %{"orient" => "records"})
        {:ok, Enum.map(rows, &Enum.into(&1, %{}))}
      end

      def stream_rows(instance) do
        # Return Stream of rows
        Stream.resource(
          fn -> {instance, 0} end,
          fn {inst, idx} ->
            case get_row(inst, idx) do
              {:ok, row} -> {[row], {inst, idx + 1}}
              {:error, :index_error} -> {:halt, {inst, idx}}
            end
          end,
          fn _ -> :ok end
        )
      end
    end
  end
end
```

**Config Usage**:
```elixir
config do
  %SnakeBridge.Config{
    classes: [
      %{
        python_path: "pandas.DataFrame",
        elixir_module: Pandas.DataFrame,
        customizers: [SnakeBridge.Customizers.DataFrame]
      }
    ]
  }
end
```

### 3. Zero-Copy via Apache Arrow

**Implementation**:
```elixir
defmodule SnakeBridge.Converters.ArrowDataFrame do
  @behaviour SnakeBridge.TypeConverter

  def from_python(df_ref, opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    # Tell Python to serialize to Arrow IPC
    {:ok, arrow_bytes} = SnakeBridge.Runtime.execute_tool(
      session_id,
      "to_arrow_ipc",
      %{"df_ref" => df_ref}
    )

    # Decode in Elixir (using Arrow library)
    {:ok, Explorer.DataFrame.from_arrow_ipc(arrow_bytes)}
  end

  def to_python(%Explorer.DataFrame{} = df, opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    # Serialize to Arrow IPC
    arrow_bytes = Explorer.DataFrame.to_arrow_ipc(df)

    # Send to Python for reconstruction
    SnakeBridge.Runtime.execute_tool(
      session_id,
      "from_arrow_ipc",
      %{"arrow_bytes" => arrow_bytes}
    )
  end

  def match_quality(%Explorer.DataFrame{}), do: :exact
  def match_quality(_), do: :none
end
```

**Python Adapter Side**:
```python
import pyarrow as pa
import pandas as pd

def to_arrow_ipc(df_ref):
    df = get_instance(df_ref)
    table = pa.Table.from_pandas(df)
    sink = pa.BufferOutputStream()
    writer = pa.ipc.new_stream(sink, table.schema)
    writer.write_table(table)
    writer.close()
    return sink.getvalue().to_pybytes()

def from_arrow_ipc(arrow_bytes):
    reader = pa.ipc.open_stream(arrow_bytes)
    table = reader.read_all()
    df = table.to_pandas()
    ref = store_instance(df)
    return ref
```

### 4. Async Stream Bridging (from pyo3-asyncio)

**Implementation**:
```elixir
defmodule SnakeBridge.Async do
  @doc "Convert Python async generator to Elixir Stream"
  def from_async_generator(session_id, gen_ref) do
    Stream.resource(
      fn -> {:cont, {session_id, gen_ref}} end,
      fn
        {:cont, {sid, gref}} ->
          case next_async_value(sid, gref) do
            {:ok, value} -> {[value], {:cont, {sid, gref}}}
            {:done, _} -> {:halt, {sid, gref}}
            {:error, reason} -> raise "Async generator error: #{inspect(reason)}"
          end

        {:halt, _} = state -> {:halt, state}
      end,
      fn {sid, gref} -> close_async_generator(sid, gref) end
    )
  end

  defp next_async_value(session_id, gen_ref) do
    # Call Python's anext(generator)
    SnakeBridge.Runtime.execute_tool(
      session_id,
      "async_next",
      %{"generator_ref" => gen_ref}
    )
  end

  defp close_async_generator(session_id, gen_ref) do
    # Call Python's aclose() on generator
    SnakeBridge.Runtime.execute_tool(
      session_id,
      "async_close",
      %{"generator_ref" => gen_ref}
    )
  end
end
```

**Usage**:
```elixir
# Python async generator
{:ok, gen_ref} = PythonLib.create_async_generator(params)

# Convert to Elixir Stream
gen_ref
|> SnakeBridge.Async.from_async_generator(session_id)
|> Stream.map(&process_chunk/1)
|> Enum.take(10)
```

### 5. Standardized Error Handling (from gRPC)

**Implementation**:
```elixir
defmodule SnakeBridge.Error do
  defstruct [:code, :message, :details, :stacktrace]

  @type t :: %__MODULE__{
    code: error_code(),
    message: String.t(),
    details: map() | nil,
    stacktrace: list() | nil
  }

  @type error_code ::
    :ok |
    :cancelled |
    :invalid_argument |
    :not_found |
    :already_exists |
    :permission_denied |
    :resource_exhausted |
    :failed_precondition |
    :internal |
    :unavailable |
    :python_exception

  def from_grpc_error(grpc_error) do
    %__MODULE__{
      code: map_grpc_code(grpc_error.code),
      message: grpc_error.message,
      details: grpc_error.details,
      stacktrace: grpc_error.stacktrace
    }
  end

  defp map_grpc_code(3), do: :invalid_argument
  defp map_grpc_code(5), do: :not_found
  defp map_grpc_code(13), do: :internal
  defp map_grpc_code(14), do: :unavailable
  defp map_grpc_code(_), do: :internal
end

# Usage in adapters
defmodule MyAdapter do
  def some_method(instance, args) do
    case SnakeBridge.Runtime.call_method(instance, "method", args) do
      {:ok, result} ->
        {:ok, result}

      {:error, %SnakeBridge.Error{code: :invalid_argument, message: msg}} ->
        {:error, {:bad_argument, msg}}

      {:error, %SnakeBridge.Error{code: :python_exception, details: %{"type" => type, "value" => value}}} ->
        {:error, {:python_error, type, value}}

      {:error, %SnakeBridge.Error{code: :unavailable}} ->
        {:error, :python_session_unavailable}
    end
  end
end
```

---

## Anti-Patterns to Avoid

### 1. Automatic Type Coercion Without User Control

**Problem**: (from JPype's property customizer mistake)

Automatically converting Python properties to Elixir-style accessors "proved very problematic. It overrode certain customizers, hid intentionally exposed fields, bloated dictionary tables, and interfered with exception unwrapping."

**Lesson**: Make customizers **opt-in**, not automatic.

**SnakeBridge Rule**:
- ✅ Explicit converter registration in config
- ❌ Automatic "helpful" conversions that surprise users
- ✅ Clear precedence rules when multiple converters match

### 2. Hiding Memory Copies

**Problem**: (from PyCall.jl / reticulate)

"It's not possible for languages to share a single copy of data when they don't agree on structure." Pretending this isn't true leads to performance surprises.

**Lesson**: **Be explicit about copying**. Users should know when data is copied vs. wrapped.

**SnakeBridge Rule**:
- ✅ Document which conversions copy and which wrap
- ✅ Provide both zero-copy (Arrow) and convenience (copy) options
- ❌ Automatic copying disguised as zero-copy

### 3. Merged Event Loops for Async

**Problem**: (from pyo3-asyncio analysis)

Attempting to merge Python's asyncio event loop with another runtime (Rust tokio, Elixir BEAM) is "unnecessarily complex."

**Lesson**: **Run separate event loops** with explicit bridging.

**SnakeBridge Rule**:
- ✅ Python asyncio runs in Python process
- ✅ Elixir BEAM scheduler is separate
- ✅ Bridge via gRPC streaming
- ❌ Don't try to merge schedulers

### 4. Unclear Exception Propagation

**Problem**: (from Python C extension error handling)

"Returning NULL without setting an exception will raise a SystemError. Setting an exception but not returning NULL will succeed but leave a later runtime error."

**Lesson**: Exception handling across language boundaries must be **explicit and consistent**.

**SnakeBridge Rule**:
- ✅ Python exceptions → gRPC error codes
- ✅ gRPC errors → Elixir `{:error, reason}` tuples
- ✅ Preserve Python stacktraces in error details
- ❌ Silent failures or lost error context

### 5. Ignoring Environment Complexity

**Problem**: (from reticulate's need for multiple environment strategies)

Python environments (venv, conda, system) are complex. Ignoring this leads to dependency conflicts.

**Lesson**: **Flexible environment management** is required.

**SnakeBridge Rule**:
- ✅ Support multiple Python environment types
- ✅ Explicit configuration in config files
- ✅ Environment isolation per adapter
- ❌ Assume system Python works for everyone

### 6. Performance Over Clarity

**Problem**: (from JPype's philosophy)

"Clarity over performance" after 20 years of lessons.

**Lesson**: Simple, consistent APIs age better than clever optimizations.

**SnakeBridge Rule**:
- ✅ Optimize hot paths (type conversion, streaming)
- ✅ Keep config syntax simple and predictable
- ❌ Clever macros that obscure behavior
- ❌ "Magic" that breaks in edge cases

### 7. Language Boundary Leakage

**Problem**: (from cross-language interop research)

"Cross-language interoperability needs to bridge different language paradigms... object-oriented vs non-object-oriented, dynamic vs static typing, explicit vs automatic memory management."

**Lesson**: Don't force one language's paradigm onto the other.

**SnakeBridge Rule**:
- ✅ Python classes feel like Elixir modules
- ✅ Python functions feel like Elixir functions
- ✅ Preserve Python's duck typing where appropriate
- ❌ Force Python into OTP supervision trees (keep them separate)

---

## Proposed Plugin Architecture for SnakeBridge

### Design Goals

Based on cross-ecosystem analysis:

1. **Extensible Type Conversion** (PyO3-style traits)
2. **Opt-In Customization** (JPype customizers, not automatic)
3. **Zero-Copy Data Transfer** (Apache Arrow integration)
4. **Explicit Async Bridging** (pyo3-asyncio separate loops)
5. **Standardized Error Handling** (gRPC status codes)
6. **Flexible Environments** (reticulate-style multi-strategy)
7. **Clear Lifecycle Management** (PyCall.jl lessons)

### Architecture: Three-Layer Plugin System

```
┌─────────────────────────────────────────────────┐
│         User Application Code                  │
│  (Uses generated adapters + custom converters) │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  Layer 1: Adapter Generation Engine             │
│  - Config → AST transformation                  │
│  - Customizer injection                         │
│  - Type converter registration                  │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  Layer 2: Type Conversion & Lifecycle           │
│  - SnakeBridge.TypeConverter protocol           │
│  - SnakeBridge.Customizer protocol              │
│  - SnakeBridge.Lifecycle callbacks              │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  Layer 3: Runtime & Transport                   │
│  - gRPC streaming (via Snakepit)                │
│  - Arrow IPC for zero-copy                      │
│  - Session management                           │
│  - Error propagation                            │
└─────────────────────────────────────────────────┘
```

### Core Protocols

#### 1. TypeConverter Protocol

```elixir
defmodule SnakeBridge.TypeConverter do
  @type conversion_opts :: [
    session_id: String.t(),
    direction: :to_python | :from_python,
    hint: atom() | nil
  ]

  @callback from_python(python_value :: term(), opts :: conversion_opts()) ::
    {:ok, elixir_value :: term()} | {:error, reason :: term()}

  @callback to_python(elixir_value :: term(), opts :: conversion_opts()) ::
    {:ok, python_value :: term()} | {:error, reason :: term()}

  @callback match_quality(value :: term()) ::
    :exact | :implicit | :explicit | :none

  @callback python_type() :: String.t()
  @callback elixir_type() :: atom()
end
```

**Built-In Converters**:
- `SnakeBridge.Converters.Primitive` (int, float, string, bool, nil)
- `SnakeBridge.Converters.Collection` (list, map, tuple)
- `SnakeBridge.Converters.Binary` (bytes)
- `SnakeBridge.Converters.ArrowDataFrame` (Pandas ↔ Explorer.DataFrame)
- `SnakeBridge.Converters.ArrowTensor` (NumPy ↔ Nx.Tensor)

**User Registration**:
```elixir
# In config
config do
  %SnakeBridge.Config{
    converters: [
      # Override defaults
      {:datetime, MyApp.DateTimeConverter},
      {:decimal, MyApp.DecimalConverter},

      # Add custom types
      {:uuid, MyApp.UUIDConverter},
      {:money, MyApp.MoneyConverter}
    ]
  }
end
```

#### 2. Customizer Protocol

```elixir
defmodule SnakeBridge.Customizer do
  @type context :: %{
    config: SnakeBridge.Config.t(),
    class_name: String.t(),
    methods: [map()],
    converters: map()
  }

  @callback customize(module_ast :: Macro.t(), context :: context()) :: Macro.t()
  @callback priority() :: integer()  # Higher = applied later
end
```

**Built-In Customizers**:
- `SnakeBridge.Customizers.Documentation` (inject @doc from Python docstrings)
- `SnakeBridge.Customizers.Telemetry` (add telemetry events)
- `SnakeBridge.Customizers.Validation` (add parameter validation)

**User-Defined Example**:
```elixir
defmodule MyApp.CachingCustomizer do
  @behaviour SnakeBridge.Customizer

  def customize(ast, context) do
    # Add caching to expensive methods
    expensive_methods = ["train", "fit", "compile"]

    quote do
      unquote(ast)

      defp maybe_cache(method_name, args, fun) do
        if method_name in unquote(expensive_methods) do
          cache_key = {method_name, args}
          Cachex.fetch(:adapter_cache, cache_key, fn -> fun.() end)
        else
          fun.()
        end
      end
    end
  end

  def priority, do: 100  # Apply late
end
```

#### 3. Lifecycle Protocol

```elixir
defmodule SnakeBridge.Lifecycle do
  @callback on_session_start(session_id :: String.t(), config :: map()) :: :ok | {:error, term()}
  @callback on_session_stop(session_id :: String.t()) :: :ok
  @callback on_instance_create(session_id :: String.t(), instance_ref :: String.t(), class :: String.t()) :: :ok
  @callback on_instance_destroy(session_id :: String.t(), instance_ref :: String.t()) :: :ok
end
```

**Use Cases**:
- Resource tracking
- Metrics collection
- Cleanup hooks
- Debug logging

### Configuration Schema Extensions

#### Extended Config with Plugins

```elixir
defmodule SnakeBridge.Config do
  use Ecto.Schema

  embedded_schema do
    # Existing fields...
    field :python_module, :string
    field :version, :string

    # NEW: Plugin configuration
    embeds_one :plugins, Plugins do
      embeds_many :converters, Converter do
        field :elixir_type, :string
        field :python_type, :string
        field :module, :string  # MyApp.CustomConverter
        field :priority, :integer, default: 50
      end

      embeds_many :customizers, Customizer do
        field :module, :string  # MyApp.CustomCustomizer
        field :priority, :integer, default: 50
        field :applies_to, {:array, :string}  # ["pandas.DataFrame"]
      end

      embeds_many :lifecycle_hooks, LifecycleHook do
        field :module, :string
        field :events, {:array, :string}  # ["session_start", "instance_create"]
      end

      embeds_one :transport, Transport do
        field :type, Ecto.Enum, values: [:grpc, :msgpack, :arrow_flight]
        field :arrow_enabled, :boolean, default: true
        field :compression, Ecto.Enum, values: [:none, :lz4, :zstd]
      end
    end
  end
end
```

#### Example Configuration

```elixir
# config/snakebridge/sklearn.exs
use SnakeBridge.Config

config do
  %SnakeBridge.Config{
    python_module: "sklearn",
    version: "1.3.0",

    classes: [
      %{
        python_path: "sklearn.linear_model.LogisticRegression",
        elixir_module: SKLearn.LinearModel.LogisticRegression,

        # Apply customizers to this class
        customizers: [
          SnakeBridge.Customizers.ModelPersistence,  # Add save/load
          MyApp.SKLearnMetrics  # Add model metrics
        ]
      }
    ],

    plugins: %{
      converters: [
        # Use Arrow for NumPy arrays
        %{
          elixir_type: "Nx.Tensor",
          python_type: "numpy.ndarray",
          module: "SnakeBridge.Converters.ArrowTensor",
          priority: 100
        },

        # Custom converter for scikit-learn's LabelEncoder
        %{
          elixir_type: "MapSet",
          python_type: "sklearn.preprocessing.LabelEncoder",
          module: "MyApp.LabelEncoderConverter",
          priority: 50
        }
      ],

      customizers: [
        %{
          module: "SnakeBridge.Customizers.Telemetry",
          priority: 10,
          applies_to: :all
        },
        %{
          module: "MyApp.CachingCustomizer",
          priority: 100,
          applies_to: ["sklearn.linear_model.*"]
        }
      ],

      lifecycle_hooks: [
        %{
          module: "MyApp.ModelRegistry",
          events: ["instance_create", "instance_destroy"]
        }
      ],

      transport: %{
        type: :grpc,
        arrow_enabled: true,
        compression: :lz4
      }
    }
  }
end
```

### Code Examples: Generated Adapter with Plugins

#### Input Config

```elixir
config do
  %SnakeBridge.Config{
    python_module: "pandas",

    classes: [
      %{
        python_path: "pandas.DataFrame",
        elixir_module: Pandas.DataFrame,
        customizers: [SnakeBridge.Customizers.DataFrame]
      }
    ],

    plugins: %{
      converters: [
        %{
          elixir_type: "Explorer.DataFrame",
          python_type: "pandas.DataFrame",
          module: "SnakeBridge.Converters.ArrowDataFrame"
        }
      ]
    }
  }
end
```

#### Generated Output (Simplified)

```elixir
defmodule Pandas.DataFrame do
  @moduledoc """
  Auto-generated adapter for pandas.DataFrame

  Python: pandas.DataFrame
  Version: 2.1.0

  Customizers applied:
    - SnakeBridge.Customizers.DataFrame (priority: 50)
    - SnakeBridge.Customizers.Documentation (priority: 10)

  Converters registered:
    - Explorer.DataFrame ↔ pandas.DataFrame (via ArrowDataFrame)
  """

  @type t :: %__MODULE__{
    session_id: String.t(),
    instance_ref: String.t()
  }

  defstruct [:session_id, :instance_ref]

  # === Core Methods (from generator) ===

  @doc """
  Create a new DataFrame instance.

  Python: pandas.DataFrame(data=None, index=None, columns=None, dtype=None, copy=None)
  """
  @spec create(map()) :: {:ok, t()} | {:error, term()}
  def create(args \\ %{}) do
    session_id = SnakeBridge.Session.get_or_start()

    # Convert args using registered converters
    python_args = SnakeBridge.TypeConversion.convert_args(args, :to_python, session_id)

    with {:ok, instance_ref} <- SnakeBridge.Runtime.create_instance(
           session_id,
           "pandas.DataFrame",
           python_args
         ),
         :ok <- notify_lifecycle(:instance_create, session_id, instance_ref, "pandas.DataFrame") do
      {:ok, %__MODULE__{session_id: session_id, instance_ref: instance_ref}}
    end
  end

  @doc """
  Get head of DataFrame.

  Python: DataFrame.head(n=5)
  """
  @spec head(t(), integer()) :: {:ok, t()} | {:error, term()}
  def head(%__MODULE__{} = df, n \\ 5) do
    with {:ok, result_ref} <- SnakeBridge.Runtime.call_method(
           df.session_id,
           df.instance_ref,
           "head",
           %{"n" => n}
         ) do
      {:ok, %__MODULE__{session_id: df.session_id, instance_ref: result_ref}}
    end
  end

  # === Customizer-Added Methods ===

  @doc """
  Convert Pandas DataFrame to Elixir Explorer DataFrame (zero-copy via Arrow).

  Added by: SnakeBridge.Customizers.DataFrame
  """
  @spec to_explorer(t()) :: {:ok, Explorer.DataFrame.t()} | {:error, term()}
  def to_explorer(%__MODULE__{} = df) do
    converter = SnakeBridge.Converters.ArrowDataFrame

    converter.from_python(
      df.instance_ref,
      session_id: df.session_id,
      direction: :from_python
    )
  end

  @doc """
  Create Pandas DataFrame from Explorer DataFrame (zero-copy via Arrow).

  Added by: SnakeBridge.Customizers.DataFrame
  """
  @spec from_explorer(Explorer.DataFrame.t()) :: {:ok, t()} | {:error, term()}
  def from_explorer(%Explorer.DataFrame{} = explorer_df) do
    session_id = SnakeBridge.Session.get_or_start()
    converter = SnakeBridge.Converters.ArrowDataFrame

    with {:ok, instance_ref} <- converter.to_python(
           explorer_df,
           session_id: session_id,
           direction: :to_python
         ),
         :ok <- notify_lifecycle(:instance_create, session_id, instance_ref, "pandas.DataFrame") do
      {:ok, %__MODULE__{session_id: session_id, instance_ref: instance_ref}}
    end
  end

  @doc """
  Stream DataFrame rows as Elixir maps.

  Added by: SnakeBridge.Customizers.DataFrame
  """
  @spec stream_rows(t()) :: Enumerable.t()
  def stream_rows(%__MODULE__{} = df) do
    Stream.resource(
      fn -> {df, 0} end,
      fn {df_inst, idx} ->
        case get_row(df_inst, idx) do
          {:ok, row} -> {[row], {df_inst, idx + 1}}
          {:error, :index_error} -> {:halt, {df_inst, idx}}
        end
      end,
      fn _ -> :ok end
    )
  end

  # === Private Helpers ===

  defp get_row(%__MODULE__{} = df, idx) do
    with {:ok, row_dict} <- SnakeBridge.Runtime.call_method(
           df.session_id,
           df.instance_ref,
           "iloc",
           %{"index" => idx}
         ) do
      # Convert Python dict to Elixir map
      {:ok, Enum.into(row_dict, %{})}
    end
  end

  defp notify_lifecycle(event, session_id, instance_ref, class_name) do
    hooks = SnakeBridge.Config.get_lifecycle_hooks(event)

    Enum.each(hooks, fn hook_module ->
      apply(hook_module, :on_instance_create, [session_id, instance_ref, class_name])
    end)

    :ok
  end
end
```

### Implementation Roadmap

#### Phase 1: Foundation (v0.3.0)

- [ ] Define `SnakeBridge.TypeConverter` behaviour
- [ ] Implement built-in converters (Primitive, Collection, Binary)
- [ ] Add converter registry to Config
- [ ] Modify Generator to use registered converters
- [ ] Add converter priority/matching logic

#### Phase 2: Customizers (v0.3.1)

- [ ] Define `SnakeBridge.Customizer` behaviour
- [ ] Implement built-in customizers (Documentation, Telemetry)
- [ ] Add customizer application to Generator
- [ ] Support per-class customizer configuration

#### Phase 3: Zero-Copy (v0.4.0)

- [ ] Integrate Apache Arrow via `arrow` Elixir library
- [ ] Implement `SnakeBridge.Converters.ArrowDataFrame`
- [ ] Implement `SnakeBridge.Converters.ArrowTensor`
- [ ] Add Arrow IPC transport to Python adapter
- [ ] Benchmark vs. JSON serialization

#### Phase 4: Lifecycle Hooks (v0.4.1)

- [ ] Define `SnakeBridge.Lifecycle` behaviour
- [ ] Add session lifecycle events
- [ ] Add instance lifecycle events
- [ ] Implement example lifecycle hooks (metrics, logging)

#### Phase 5: Advanced (v0.5.0)

- [ ] Async generator bridging (Python AsyncIterator ↔ Elixir Stream)
- [ ] Streaming type converters (chunked transfer)
- [ ] Custom transport backends (MsgPack, Arrow Flight)
- [ ] Performance profiling and optimization

---

## Recommendations Summary

### Immediate Actions (Phase 1C Complete)

1. **Adopt PyO3's trait-based type conversion system**
   - Define `SnakeBridge.TypeConverter` behaviour
   - Implement match quality levels (exact/implicit/explicit/none)
   - Add converter registry to Config schema

2. **Implement JPype's customizer pattern**
   - Define `SnakeBridge.Customizer` behaviour
   - Make customizers opt-in, not automatic
   - Support per-class customizer application

3. **Integrate Apache Arrow for zero-copy**
   - Add `arrow` dependency
   - Implement DataFrame/Tensor converters
   - Benchmark performance gains

4. **Standardize error handling**
   - Map gRPC status codes to SnakeBridge error types
   - Preserve Python stacktraces
   - Document error semantics

5. **Add lifecycle hooks**
   - Define `SnakeBridge.Lifecycle` behaviour
   - Emit events for session/instance lifecycle
   - Enable user-defined cleanup logic

### Long-Term Vision

SnakeBridge should become:

- **As elegant as PyO3** - Trait-based extensibility with derive-like config macros
- **As mature as JPype** - 20+ years of lessons distilled into design decisions
- **As fast as Arrow** - Zero-copy for data-intensive workloads
- **As reliable as gRPC** - Standardized errors, streaming, observability

**Target Developer Experience**:
```elixir
# config/snakebridge/my_lib.exs
use SnakeBridge.Config

config do
  %SnakeBridge.Config{
    python_module: "my_ml_lib",

    # Zero-config for 90% use cases
    classes: [
      %{python_path: "my_ml_lib.Model", elixir_module: MyMLLib.Model}
    ],

    # Opt-in customization for advanced users
    plugins: %{
      converters: [%{module: MyApp.CustomConverter}],
      customizers: [%{module: MyApp.CachingCustomizer}]
    }
  }
end

# Usage - feels like native Elixir
{:ok, model} = MyMLLib.Model.create(%{layers: [128, 64, 32]})
{:ok, result} = MyMLLib.Model.predict(model, input_data)  # Zero-copy if Arrow
```

---

## References

### Primary Sources

1. [PyO3 Type Conversion System](https://pyo3.rs/main/conversions/traits.html)
2. [PyO3 Conversion Traits Documentation](https://pyo3.rs/main/conversions/traits)
3. [pyo3-async-runtimes GitHub](https://github.com/PyO3/pyo3-async-runtimes)
4. [JPype User Guide](https://jpype.readthedocs.io/en/latest/userguide.html)
5. [JPype Developer Guide](https://jpype.readthedocs.io/en/latest/develguide.html)
6. [PyCall.jl GitHub](https://github.com/JuliaPy/PyCall.jl)
7. [reticulate R Package](https://rstudio.github.io/reticulate/)
8. [Passing Arrow Data Between R and Python](https://blog.djnavarro.net/posts/2022-09-09_reticulated-arrow/)
9. [Apache Arrow C Data Interface](https://arrow.apache.org/blog/2020/05/03/introducing-arrow-c-data-interface/)
10. [Apache Arrow Zero-Copy Sharing](https://voltrondata.com/blog/zero-copy-sharing-using-apache-arrow-and-golang)
11. [gRPC Error Handling](https://grpc.io/docs/guides/error/)
12. [gRPC Python Best Practices](https://speedscale.com/blog/using-grpc-with-python/)
13. [Python C Extension Error Handling](https://docs.python.org/3/c-api/exceptions.html)
14. [Cross-Language Interoperability Challenges](https://chrisseaton.com/truffleruby/cross-language-interop.pdf)

### Additional Reading

- [PyO3 Architecture](https://github.com/PyO3/pyo3/blob/main/Architecture.md)
- [JPype ChangeLog](https://jpype.readthedocs.io/en/latest/ChangeLog-0.7.html)
- [Apache Arrow IPC Format](https://arrow.apache.org/docs/cpp/ipc.html)
- [gRPC Streaming Best Practices](https://grpc.io/docs/what-is-grpc/core-concepts/)

---

**End of Document**

This analysis synthesizes patterns from 7 mature cross-language projects with 100+ combined years of production experience. The proposed SnakeBridge plugin architecture combines the best ideas: PyO3's trait elegance, JPype's customizer flexibility, Arrow's zero-copy performance, and gRPC's standardized streaming.

**Next Steps**: Implement Phase 1 (TypeConverter behaviour + built-in converters) in SnakeBridge v0.3.0.
