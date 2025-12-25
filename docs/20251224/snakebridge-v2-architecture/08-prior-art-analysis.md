# Prior Art Analysis: Python-to-Other-Language Bridges

**Document**: Prior Art Analysis for SnakeBridge v2
**Date**: 2025-12-24
**Purpose**: Analyze existing Python bridging solutions to inform SnakeBridge v2 architecture redesign

---

## Executive Summary

This document analyzes six major Python bridging projects to extract architectural patterns, type handling strategies, documentation approaches, and lessons learned for the SnakeBridge v2 redesign. The key finding is that **compile-time introspection + trait-based type conversion + automatic stub generation** (PyO3/nanobind approach) represents the state-of-the-art, while **runtime introspection + message passing** (ErlPort approach) offers better flexibility at the cost of performance.

**Key Recommendations for SnakeBridge v2**:
1. Adopt trait-like type conversion system (inspired by PyO3's `FromPyObject`/`IntoPyObject`)
2. Generate `.pyi` stub files automatically (like nanobind's stubgen)
3. Use runtime introspection for manifest generation, compile-time for production (hybrid approach)
4. Maintain ErlPort's message-passing architecture but optimize with vectorcalls
5. Consider nanobind's "compact objects" pattern for memory efficiency

---

## 1. PyO3/Maturin (Rust ↔ Python)

### Overview
PyO3 is a Rust library that creates native Python modules in Rust or embeds Python in Rust programs. Maturin is the build tool that packages these modules into Python wheels.

**Repository**: https://github.com/PyO3/pyo3
**Architecture**: Compile-time binding with procedural macros

### Type Handling Approach

#### Core Trait System
PyO3 uses a sophisticated **trait-based type conversion system**:

```rust
// Python → Rust
trait FromPyObject<'source> {
    fn extract(ob: &'source PyAny) -> PyResult<Self>;
}

// Rust → Python (modern)
trait IntoPyObject<'py> {
    type Target;
    fn into_pyobject(self, py: Python<'py>) -> Result<Bound<'py, Self::Target>>;
}

// Rust → Python (legacy)
trait IntoPy<T> {
    fn into_py(self, py: Python) -> T;
}
```

**Key Design Decisions**:
- Requires GIL token (`Python<'py>`) for all conversions (safety)
- Can't use standard `From`/`Into` traits due to GIL requirement
- Supports both owned (`Bound`) and borrowed (`Borrowed`) smart pointers to avoid reference counting overhead
- Automatic implementations for standard library types (Vec, HashMap, etc.)

#### Derive Macros for Custom Types
```rust
#[derive(IntoPyObject)]
struct Point { x: f64, y: f64 }  // → PyDict with fields as keys

#[derive(IntoPyObject)]
struct RGB(u8, u8, u8)  // → PyTuple
```

**Strengths**:
- Compile-time type safety
- Zero-cost abstractions
- Automatic memory management across GC boundaries
- Support for complex types (generics, lifetimes)

**Weaknesses**:
- Requires Rust knowledge for custom types
- Type conversions must be known at compile time
- No runtime introspection of Rust types

### Documentation Generation

#### Text Signatures
```rust
#[pyfunction]
#[pyo3(text_signature = "(x, y, /)")]
fn calculate(x: i32, y: i32) -> i32 { x + y }
```

#### Stub Generation Ecosystem
- **pyo3-stubgen**: External tool that generates `.pyi` files
- **pyo3-stub-gen**: Alternative stub generator
- **Manual stubs**: Many projects write `.pyi` files manually

**Issue**: No built-in stub generation (community tools vary in quality)

### Introspection Approach

**Compile-time only**:
- Uses C++11-style template metaprogramming (via Rust macros)
- Type information embedded in procedural macro expansion
- No runtime reflection of Rust types
- Python side uses standard `help()`, `inspect` module

### Architecture Patterns

1. **Procedural Macros for Zero Boilerplate**:
   ```rust
   #[pyclass]
   struct MyClass { field: i32 }

   #[pymethods]
   impl MyClass {
       #[new]
       fn new(value: i32) -> Self { MyClass { field: value } }

       fn method(&self) -> i32 { self.field }
   }
   ```

2. **GIL Token Threading**:
   - All Python operations require explicit `Python<'py>` token
   - Enforces thread safety at compile time
   - Prevents data races across Python/Rust boundary

3. **Smart Pointer System**:
   - `Bound<'py, T>`: Owned reference (increments refcount)
   - `Borrowed<'a, 'py, T>`: Borrowed reference (no refcount change)
   - Optimizes for performance-critical paths

4. **Build Tool Integration**:
   - Maturin handles cross-compilation
   - Automatic wheel building for PyPI
   - Development mode with `pip install -e`

### Lessons Learned

**Good**:
- Trait-based type conversion is elegant and extensible
- Compile-time safety prevents entire classes of bugs
- Procedural macros eliminate boilerplate
- GIL token pattern ensures thread safety

**Bad**:
- Steep learning curve for non-Rust developers
- Stub generation is an afterthought (not integrated)
- No runtime introspection makes dynamic scenarios difficult
- Build complexity (requires Rust toolchain)

**Applicable to SnakeBridge v2**:
- Adopt protocol/behaviour-based type conversion in Elixir
- Generate type specs automatically (like stubs)
- Consider compile-time mode for production deployments
- Learn from GIL token pattern for process safety

---

## 2. pybind11 (C++ ↔ Python)

### Overview
Header-only library that exposes C++ types in Python using near-identical syntax to Boost.Python. Goals: minimize boilerplate through compile-time introspection.

**Repository**: https://github.com/pybind/pybind11
**Architecture**: Template metaprogramming with C++11

### Type Handling Approach

#### Type Caster System
Core template class: `type_caster<T>`

**Three Fundamental Approaches**:

1. **Wrapped Types** (`py::class_<T>`):
   ```cpp
   py::class_<MyClass>(m, "MyClass")
       .def("method", &MyClass::method);
   ```
   - Original C++ object stays intact
   - Python wrapper added as outer layer
   - No copying, just pointer wrapping

2. **Automatic Conversion** (Copy-based):
   ```cpp
   std::vector<int> → list (copy)
   std::map<K, V> → dict (copy)
   ```
   - Convenient but expensive for large data
   - Many built-in conversions (STL containers)

3. **Python Objects** (`py::object` family):
   ```cpp
   py::list, py::dict, py::tuple
   ```
   - Direct manipulation of Python types in C++

#### Custom Type Casters
```cpp
namespace pybind11 { namespace detail {
    template <> struct type_caster<MyType> {
        PYBIND11_TYPE_CASTER(MyType, _("MyType"));

        bool load(handle src, bool convert);
        static handle cast(const MyType &src, return_value_policy policy, handle parent);
    };
}}
```

**Strengths**:
- Flexible type conversion strategies
- Explicit control over copy vs reference semantics
- Extensive STL support out-of-the-box

**Weaknesses**:
- Template compilation times can be long
- Binary size bloat with many bindings
- Runtime overhead from type checks

### Documentation Generation

#### Built-in Signature Generation
```cpp
// Automatic docstring:
// "method(self: MyClass, x: int, y: int) -> int"
m.def("method", &method);

// Disable with:
py::options().disable_function_signatures();
```

#### pybind11_mkdoc Tool
Extracts C++ comments → Python docstrings:

```cpp
// C++ header
/// Calculate the sum
/// @param x First number
/// @param y Second number
int add(int x, int y);

// Usage in bindings
m.def("add", &add, DOC(add));
```

#### pybind11-stubgen Tool
External utility to generate `.pyi` files from extension modules:

```bash
pybind11-stubgen mymodule -o stubs/
```

**Issues**:
- Extracts from docstrings (brittle)
- Generic signatures for overloaded functions: `(*args, **kwargs) -> Any`
- MyPy's stubgen doesn't preserve docstrings

**Evolution**: nanobind solves this with `__nb_signature__` property

### Introspection Approach

**Compile-time template introspection**:
- C++11 variadic templates
- `std::is_same`, `std::enable_if` for SFINAE
- Type information inferred from function signatures
- No runtime reflection of C++ types

**Runtime**:
- Python's `help()` works on generated bindings
- `inspect.signature()` shows generic signatures (limitation)

### Architecture Patterns

1. **Header-Only Design**:
   - No separate compilation step
   - Include headers, compile once
   - Trade-off: longer compilation, simpler deployment

2. **Method Chaining Builder Pattern**:
   ```cpp
   py::class_<MyClass>(m, "MyClass")
       .def(py::init<int>())
       .def("method", &MyClass::method)
       .def_readwrite("field", &MyClass::field);
   ```

3. **Return Value Policies**:
   ```cpp
   .def("get_data", &get_data, py::return_value_policy::reference)
   ```
   - Explicit control over ownership
   - Prevents dangling references

4. **Move Semantics**:
   - C++11 move constructors used automatically
   - Efficient transfer of large objects

5. **Overload Resolution**:
   - Automatic based on argument types
   - Can be brittle with ambiguous cases

### Lessons Learned

**Good**:
- Three-tier type conversion strategy is well thought out
- Builder pattern makes bindings readable
- Automatic signature generation (when it works)
- Extensive production use (battle-tested)

**Bad**:
- Compilation time scales poorly
- Binary size bloat
- Stub generation is external and imperfect
- Template error messages are cryptic
- Performance overhead from type checks

**Applicable to SnakeBridge v2**:
- Offer multiple type conversion strategies (copy, reference, direct)
- Builder pattern for manifest generation
- Learn from return value policy concept (ownership transfer)
- Integrate stub generation from the start (don't make it external)

**Note**: See nanobind analysis for modern improvements

---

## 3. nanobind (C++ ↔ Python) - pybind11's Successor

### Overview
Created by the same author as pybind11. Goals: ~4× faster compilation, ~5× smaller binaries, ~10× lower runtime overhead. Philosophy shift: target smaller C++ subset, make codebases adapt to the tool.

**Repository**: https://github.com/wjakob/nanobind
**Benchmark**: https://nanobind.readthedocs.io/en/latest/benchmark.html

### Key Architectural Improvements Over pybind11

#### 1. Compact Objects (Memory Layout)
**pybind11**: Python object → holder (std::unique_ptr) → C++ object (56 bytes overhead)
**nanobind**: Python object ⊕ C++ object co-located (24 bytes overhead)

- 2.3× reduction in per-instance overhead
- Less pointer chasing (cache-friendly)
- Holders removed entirely (source of complexity)

#### 2. Better Data Structures
- Replace `std::unordered_map` with `tsl::robin_map`
- Faster lookups for type registration
- Lower memory footprint

#### 3. PEP 590 Vectorcalls
- Modern calling convention (Python 3.8+)
- Bypasses tuple/dict creation for arguments
- Significant speedup for function calls

#### 4. Free-Threading Support (Python 3.13+)
- Localized locking scheme (per-type locks)
- Better multi-core scaling
- pybind11 has global lock contention bottleneck

#### 5. Stable ABI Support
- Compile once, run on all Python 3.12+ versions
- Smaller distribution (one wheel per platform)
- Faster CI/CD

#### 6. Integrated Stub Generation

**`__nb_signature__` Property**:
```python
>>> my_function.__nb_signature__
Signature(args=[Arg(name='x', type='int'), ...], return_type='str')
```

- Structured information about types, overloads, defaults
- No brittle docstring parsing
- High-quality stub generation built-in:

```bash
python -m nanobind.stubgen mymodule
```

### Type Handling Changes

Similar to pybind11 but:
- No multiple inheritance (simplification)
- No holder types (objects must be co-locatable)
- Stricter about object ownership

### Trade-offs (Features Removed)

**Removed from pybind11**:
1. Multiple inheritance support
2. Embedding Python in executables
3. Multiple independent interpreters
4. Some exotic holder types

**Rationale**: These features caused most of pybind11's complexity. Removing them allows dramatic simplification.

### Performance Numbers

| Metric | pybind11 | nanobind | Improvement |
|--------|----------|----------|-------------|
| Compile time | Baseline | 2.7-4.4× faster | 4.4× |
| Binary size | Baseline | 3-5× smaller | 5× |
| Simple function call | Baseline | ~3× faster | 3× |
| Class passing | Baseline | ~10× faster | 10× |

### Lessons Learned

**Good**:
- **Simplification pays off**: Removing features improved everything
- **Integrated stubgen**: First-class stub generation is critical
- **Memory layout matters**: Co-location is a huge win
- **Modern Python features**: PEP 590 vectorcalls are important
- **Philosophy clarity**: "Adapt code to tool" enables optimization

**Bad**:
- Breaking changes from pybind11 (migration cost)
- Smaller feature set (trade-off accepted)

**Applicable to SnakeBridge v2**:
- **Ruthlessly simplify**: Remove features if they add complexity
- **Stub generation is non-negotiable**: Build it in from day one
- **Memory layout**: Consider co-locating Elixir/Python data where possible
- **Modern protocols**: Use latest Erlang/Elixir features (not legacy)
- **Vectorcalls**: Investigate if Snakepit can use PEP 590
- **Stable interface**: Make cross-version compatibility a priority

---

## 4. JPype (Java ↔ Python)

### Overview
Provides full access to Java from Python by embedding a JVM in the Python process via JNI (Java Native Interface).

**Repository**: https://github.com/jpype-project/jpype
**Architecture**: In-process JVM embedding (vs. Py4J's socket communication)

### Type Handling Approach

#### Automatic Primitive Conversions
```python
# Python → Java
int → int/long
float → float/double
str → String
bool → boolean

# Java → Python
java.lang.String → str
java.lang.Integer → int
```

#### Collection Conversions
```python
# Bidirectional
list ↔ java.util.ArrayList
dict ↔ java.util.HashMap
```

#### Wrapper Classes for Complex Types
When automatic conversion isn't appropriate:
```python
jarray = jpype.JArray(jpype.JInt)([1, 2, 3])
jclass = jpype.JClass('com.example.MyClass')
jobj = jclass()  # Create instance
```

#### Type Overloading Resolution
Java methods can be overloaded; JPype matches based on:
1. Argument count
2. Type compatibility
3. Best-match algorithm

**Issue**: Ambiguous cases can fail or pick wrong overload

### Introspection and Reflection

**Full Java Reflection API Access**:
```python
import jpype

# Get class
MyClass = jpype.JClass('com.example.MyClass')

# Introspect methods
for method in MyClass.class_.getDeclaredMethods():
    print(f"{method.getName()}: {method.getParameterTypes()}")

# Introspect fields
for field in MyClass.class_.getDeclaredFields():
    print(f"{field.getName()}: {field.getType()}")

# Call reflected method
method = MyClass.class_.getMethod('myMethod', [jpype.JClass('java.lang.String')])
result = method.invoke(obj, ['arg'])
```

**Strengths**:
- Runtime introspection of all Java types
- Access to private methods (via `setAccessible`)
- Dynamic proxy creation (implement Java interfaces in Python)

### Documentation

**No automatic documentation generation**:
- Uses Java's existing Javadoc
- Python `help()` shows limited info
- No `.pyi` stub generation

**Workaround**: Some projects manually write stubs for type checkers

### Architecture Patterns

#### 1. In-Process JVM
```python
jpype.startJVM(classpath=['my.jar'])
# JVM runs in same process as Python
# Fast: no serialization overhead
# Risk: JVM crash = Python crash
```

vs. **Py4J**: Separate processes, socket communication (slower but safer)

#### 2. Exception Bridging
```python
try:
    java_method()
except jpype.JException as e:
    print(f"Java exception: {e.message()}")
    print(f"Stack trace: {e.stacktrace()}")
```

Java exceptions → Python exceptions (preserving stack trace)

#### 3. Memory Management
- Python GC and Java GC run independently
- JPype maintains references to prevent premature collection
- Circular references across boundary can cause leaks

#### 4. Threading
- Python threads can call Java (GIL released during JNI calls)
- Java threads can call Python (must acquire GIL)
- Deadlock potential if not careful

### Lessons Learned

**Good**:
- In-process embedding is fast (no serialization)
- Full reflection API access enables rich introspection
- Exception bridging preserves debugging info
- Automatic type conversion for common cases

**Bad**:
- No automatic documentation generation
- Type ambiguity in overloaded methods
- Memory leak potential with circular references
- Process crash risk (JVM crash = Python crash)
- No type hints (.pyi stubs)

**Applicable to SnakeBridge v2**:
- Snakepit's out-of-process model is safer (crashes isolated)
- Reflection API is powerful: use Python's `inspect` module extensively
- Exception bridging: preserve Python tracebacks in errors
- Consider automatic type conversion for common Elixir/Python types
- **Don't**: Skip documentation generation (big mistake in JPype)

**Key Insight**: Reflection enables automatic manifest generation

---

## 5. ErlPort (Erlang ↔ Python) - SnakeBridge's Predecessor

### Overview
ErlPort is the OG Erlang-Python bridge (created 2009). It's the architecture that Snakepit evolved from, using Erlang's port protocol + external term format.

**Repository**: https://github.com/erlport/erlport
**Documentation**: http://erlport.org/docs/

### Architecture

#### Core Design: Port Protocol
```erlang
% Erlang side
{ok, Pid} = python:start().
Result = python:call(Pid, 'module', 'function', [arg1, arg2]).
```

```python
# Python side (erlport library)
from erlport.erlang import call

result = call('erlang_module', 'erlang_function', [arg1, arg2])
```

**Key Properties**:
- **Message passing**: No shared memory
- **Process isolation**: Python crash doesn't crash Erlang
- **Bidirectional**: Both sides can call the other
- **Multiple instances**: One Erlang process per Python instance

#### Communication Protocol

**Erlang Port Protocol**:
- Byte-oriented interface to external programs
- Packet framing (packet=1, 2, or 4 byte length prefix)
- stdin/stdout communication (or custom file descriptors)

**Serialization**: Erlang External Term Format (ETF)
- Binary protocol for Erlang terms
- Compact and efficient
- Language-agnostic (can be implemented anywhere)

### Type Mapping

#### Built-in Conversions

| Erlang Type | Python Type | Notes |
|-------------|-------------|-------|
| `integer()` | `int` | Python 3 has arbitrary precision |
| `float()` | `float` | IEEE 754 double |
| `binary()` | `bytes` | Direct mapping |
| `atom()` | `Atom('atom')` | Custom wrapper class |
| `list()` | `list` | Recursive conversion |
| `tuple()` | `tuple` | Recursive conversion |
| `map()` | `dict` | Keys must be hashable |

#### Custom Type Classes

```python
from erlport.erlang import Atom, String, BitBinary

# Erlang atom
Atom('ok')

# Erlang string (list of integers) vs Python str
String('hello')  # → [104, 101, 108, 108, 111]

# Bitstring (non-byte-aligned)
BitBinary(b'data', 5)  # 5 bits
```

#### Custom Encoders/Decoders

```python
from erlport.erlang import encode, decode

# Encode Python term → binary
binary = encode({'key': 'value'})

# Decode binary → Python term
term = decode(binary)
```

**Extension Point**: Can create custom encoders for higher-level types

### Introspection Approach

**Runtime introspection only**:
```python
import inspect

members = inspect.getmembers(module)
signature = inspect.signature(function)
```

**No code generation**: Calls are fully dynamic

### Documentation

**None**: ErlPort doesn't generate documentation. You must:
- Read Python docstrings manually
- Write Erlang specs manually
- Maintain documentation separately

**This is a huge gap** that SnakeBridge addressed with manifests

### Architecture Patterns

#### 1. Python Instance as GenServer
```erlang
% LFE wrapper (py library built on ErlPort)
(set pid (py:start))
(py:call pid 'math 'sqrt '(16))
```

Each Python instance is a gen_server managing:
- Python interpreter process
- Message queue
- State (loaded modules, etc.)

#### 2. Message Handler Pattern
```python
from erlport.erlang import set_message_handler

def handle_message(msg):
    # Process message from Erlang
    return response

set_message_handler(handle_message)
```

Allows Erlang to send arbitrary messages to Python (not just function calls)

#### 3. Compression Support
```python
Port(packet=1, compressed=True)  # zlib compression
```

For large data transfers

#### 4. Error Handling
```erlang
case python:call(Pid, 'module', 'func', []) of
    {ok, Result} -> Result;
    {error, {Class, Error, Traceback}} -> handle_error(Error)
end
```

Python exceptions serialized with:
- Exception class
- Error message
- Traceback (string)

### Lessons Learned

**Good**:
- **Process isolation is brilliant**: Crashes don't propagate
- **Message passing scales**: Can distribute across nodes
- **Bidirectional calls**: Symmetric relationship
- **ETF is efficient**: Compact binary format
- **Multiple instances**: Easy to parallelize

**Bad**:
- **No documentation generation**: Huge gap
- **No type checking**: Fully dynamic (errors at runtime)
- **Synchronous calls block**: Need timeouts everywhere
- **No streaming**: Request-response only (SnakeBridge fixed this)
- **Manual type wrapping**: `Atom()`, `String()` classes are verbose

**Applicable to SnakeBridge v2**:
- **Keep process isolation**: This is a core strength
- **Keep message passing**: Don't try to be in-process
- **Add streaming**: SnakeBridge's streaming support is critical
- **Generate documentation**: This is where SnakeBridge shines
- **Add type safety**: Static analysis + manifests
- **Consider async calls**: Don't block Elixir processes

**Key Evolution**: SnakeBridge → Snakepit added gRPC, streaming, better performance

---

## 6. python-bridge / JSPyBridge (Node.js ↔ Python)

### Overview
Multiple Node.js-Python bridges exist with different architectures. JSPyBridge is the most advanced, offering "real interop" with proxy objects.

**Repositories**:
- JSPyBridge: https://github.com/extremeheat/JSPyBridge
- node-python-bridge: https://github.com/Submersible/node-python-bridge
- PyBridge (TypeScript): https://marcjschmidt.de/pybridge

### Architecture Approaches

#### 1. JSON Serialization (python-bridge, node-python-bridge)

**Architecture**:
- Spawn Python interpreter subprocess
- Communicate via stdin/stdout
- Serialize arguments as JSON
- Parse results from JSON

```javascript
const pythonBridge = require('python-bridge');
const python = pythonBridge();

python.ex`import math`
const result = await python`math.sqrt(16)`;  // 4.0
```

**Limitations**:
- Only JSON-serializable types
- No custom objects
- No callbacks
- High serialization overhead

#### 2. Proxy Objects (JSPyBridge)

**Architecture**:
- Bidirectional RPC over communication pipe
- Proxy objects represent foreign references
- Methods called on proxies → RPC to other side

```javascript
const { PythonBridge } = require('jspybridge');
const bridge = new PythonBridge();

// Get Python module as proxy
const np = bridge.importModule('numpy');

// Call method on proxy (RPC under the hood)
const arr = np.array([1, 2, 3, 4]);
const mean = arr.mean();  // RPC calls
```

**Key Features**:
- **Lazy transfer**: Objects stay on native side until needed
- **Callbacks work**: Can pass JavaScript functions to Python
- **Bi-directional**: Python can call JavaScript
- **Automatic GC**: Proxy lifecycle managed automatically

**Transfer Methods**:
```javascript
// Transfer via JSON (for serializable objects)
const native = foreignObj.valueOf();

// Transfer via binary (for large data)
const native = await foreignObj.blobValueOf();

// Keep as proxy (no transfer)
foreignObj.method();  // RPC call
```

### Type Conversion Strategies

#### python-bridge
```javascript
// JavaScript → Python
boolean → bool
number → float
string → str
null/undefined → None
Array → list
Object → dict
```

**Issue**: Loss of precision (JS number → Python float, even for integers)

#### node-python
```javascript
// Workaround for 64-bit integers
// Convert to string, use bignumber.js
const bigInt = BigNumber(pythonResult);
```

#### PyBridge (TypeScript-focused)
```typescript
// Type-safe wrappers
interface PythonFunction {
    (...args: JSONSerializable[]): Promise<JSONSerializable>;
}
```

Automatic serialization/deserialization with TypeScript type checking

#### JSPyBridge Proxy Types
```javascript
// Foreign reference (no transfer)
const obj = py.import('module').get_object();
typeof obj;  // 'PyObject' (proxy)

// Convert to native
const native = obj.valueOf();  // JSON serialization
typeof native;  // 'object' (JavaScript object)
```

### Documentation Generation

**None of these projects generate documentation automatically**:
- Rely on Python's existing docstrings
- No `.d.ts` TypeScript definitions generated
- Manual type definition files for TypeScript

**PyBridge** (TypeScript):
- Requires manual type definitions
- Type safety only if you write `.d.ts` files

### Introspection

**JSPyBridge**:
```javascript
// Python introspection accessible via proxy
const members = py.import('inspect').getmembers(obj);
```

**Others**: Limited introspection (JSON bridge can't represent introspection results well)

### Architecture Patterns

#### 1. Subprocess Management
```javascript
const python = spawn('python', ['-u', 'bridge.py']);
// -u flag: unbuffered I/O (critical for IPC)
```

#### 2. Line-Based Protocol (simple bridges)
```
→ {"method": "call", "module": "math", "func": "sqrt", "args": [16]}
← {"result": 4.0}
```

#### 3. RPC Protocol (JSPyBridge)
```
→ {"type": "call", "ref": 123, "method": "mean", "args": []}
← {"type": "return", "ref": 123, "value": 2.5}
```

With reference tracking for proxy objects

#### 4. Memory-Mapped Communication (@platformatic/python-node)

**Modern approach** (2024+):
- Embeds Python interpreter in Node process (via Rust bridge)
- Speaks ASGI protocol
- Direct memory sharing (no serialization to HTTP)
- Fastest option but most complex

### Lessons Learned

**Good (JSPyBridge)**:
- **Proxy objects are powerful**: No need to serialize everything
- **Callbacks enable rich patterns**: Python can call JavaScript
- **Lazy transfer is efficient**: Only serialize when needed
- **Bidirectional is useful**: Symmetric relationship

**Bad**:
- **JSON serialization is limiting**: Can't represent many types
- **No documentation generation**: Major gap
- **Process management complexity**: Spawning, killing, error handling
- **No type safety**: Runtime errors only

**Good (Memory-mapped approach)**:
- **Fastest possible**: No serialization overhead
- **Shared memory**: Direct access to data structures

**Bad (Memory-mapped)**:
- **Complex**: Requires Rust bridge code
- **Fragile**: Process crash risk
- **Platform-specific**: Harder to maintain

**Applicable to SnakeBridge v2**:
- **Proxy concept**: Could Elixir have "Python proxies" for complex objects?
- **Lazy transfer**: Don't serialize large data unless needed
- **Callbacks**: Elixir functions as Python callbacks (via manifest?)
- **Don't do memory-mapped**: Stick with process isolation
- **Generate docs**: This is a competitive advantage

**Key Insight**: Multiple strategies (JSON, proxy, memory) suggest one-size-fits-all doesn't work

---

## 7. Other Elixir-Python Bridges

### Survey of Elixir Ecosystem

Based on research, existing Elixir-Python bridges:

1. **ErlPort** (via Export wrapper)
   - Export: Elixir wrapper around ErlPort
   - More idiomatic Elixir API
   - Same underlying architecture (port protocol)

2. **Pyrlang**
   - Python appears as Erlang node
   - Can participate in distributed Erlang cluster
   - Heavier weight (full node protocol)

3. **Snakepit**
   - Modern evolution of ErlPort approach
   - gRPC instead of port protocol
   - Better performance, streaming support
   - What SnakeBridge currently uses

4. **Pythonx**
   - Embeds Python directly in BEAM VM
   - Experimental, not production-ready
   - Higher performance but less isolation

5. **Rustler + PyO3** (NIFs)
   - Use Rust as intermediary
   - Rustler: Elixir ↔ Rust
   - PyO3: Rust ↔ Python
   - Compile-time safety but complex

### Architecture Comparison

| Bridge | Architecture | Isolation | Performance | Complexity |
|--------|-------------|-----------|-------------|------------|
| ErlPort | Port protocol | Process | Medium | Low |
| Pyrlang | Distributed Erlang | Process/Node | Medium | Medium |
| Snakepit | gRPC | Process | High | Medium |
| Pythonx | Embedded | In-process | Highest | High |
| Rustler+PyO3 | NIF chain | In-process | Highest | Very High |

### Lessons Learned

**Process isolation is the winner for Elixir**:
- BEAM's strength is fault tolerance
- In-process embedding sacrifices this
- Out-of-process matches Elixir philosophy

**gRPC is modern evolution**:
- ErlPort → Snakepit shows evolution
- Port protocol → gRPC is natural progression
- Better performance, streaming, standardization

**SnakeBridge fills unique niche**:
- Other bridges are low-level (manual calls)
- SnakeBridge adds manifest layer (curation)
- Documentation generation is unique
- Compile-time code generation is unique

**Gap**: None have integrated stub/typespec generation like nanobind

---

## Cross-Project Comparison Matrix

| Project | Type Safety | Doc Gen | Introspection | Architecture | Performance | Complexity |
|---------|-------------|---------|---------------|--------------|-------------|------------|
| **PyO3** | Compile-time (Rust) | Manual stubs | Compile-time | In-process NIF | Highest | High |
| **pybind11** | Compile-time (C++) | External tools | Compile-time | In-process NIF | High | High |
| **nanobind** | Compile-time (C++) | Integrated | Compile-time | In-process NIF | Highest | Medium |
| **JPype** | Runtime (dynamic) | None | Runtime (full) | In-process JVM | High | Medium |
| **ErlPort** | None (dynamic) | None | Runtime | Out-of-process | Medium | Low |
| **JSPyBridge** | None (proxy) | None | Runtime (proxy) | Out-of-process | Medium | Medium |
| **SnakeBridge** | Manifest (hybrid) | Manifest-based | Runtime + manifest | Out-of-process | Medium | Low-Medium |

---

## Key Patterns Extracted

### Pattern 1: Type Conversion Strategies

**Three fundamental approaches** (from pybind11, applicable everywhere):

1. **Wrapped/Proxy**: Keep object in native language, add thin wrapper
   - **When**: Large objects, complex objects, frequent method calls
   - **Trade-off**: RPC overhead per call, but no serialization cost
   - **Example**: pybind11's `py::class_`, JSPyBridge proxies

2. **Copy/Serialize**: Convert to target language's equivalent type
   - **When**: Simple data, cross-boundary transfer, long-term storage
   - **Trade-off**: Serialization cost, but native access after
   - **Example**: ErlPort's ETF, JSON bridges, PyO3 automatic conversions

3. **Shared/Direct**: Reference same memory from both languages
   - **When**: Maximum performance, large data, tight coupling acceptable
   - **Trade-off**: Complexity, crash risk, but zero overhead
   - **Example**: Memory-mapped Node.js bridge, some NumPy interop

**SnakeBridge v2 should support all three**, letting users choose per-type.

### Pattern 2: Documentation Generation

**Evolution observed**:
1. **Manual** (JPype, ErlPort): No generation, manual docs
2. **External Tools** (pybind11): Separate stubgen, brittle
3. **Integrated** (nanobind): Built-in, first-class, high-quality

**SnakeBridge's manifest approach** is closest to #3 but could improve:
- Currently: Manifests are manually curated
- Future: Auto-generate manifests from introspection
- Generate both Elixir typespecs AND Python `.pyi` stubs
- Keep human-in-the-loop for curation

### Pattern 3: Introspection Timing

**Spectrum observed**:
- **Compile-time only** (PyO3, pybind11): Fast runtime, inflexible
- **Runtime only** (ErlPort, JPype): Flexible, slower, error-prone
- **Hybrid** (SnakeBridge manifests, nanobind signatures): Best of both

**Recommendation**: Hybrid approach
- Use runtime introspection to generate manifests (development)
- Use manifests for compile-time generation (production)
- Support both runtime and compile-time modes

### Pattern 4: Error Handling

**Common pattern** across all projects:
```
Foreign exception → Native exception wrapper
- Preserve exception type/class name
- Preserve error message
- Preserve stack trace (if possible)
- Add context (which bridge, which call)
```

**ErlPort approach**:
```erlang
{error, {PythonExceptionClass, Message, Traceback}}
```

**PyO3 approach**:
```rust
Err(PyErr::new::<exceptions::PyValueError, _>("message"))
```

**SnakeBridge could improve**:
- Structured error types (not just strings)
- Preserve Python traceback in Elixir exceptions
- Add call context (manifest name, function, args)

### Pattern 5: Memory Management

**Two philosophies**:

1. **GC Bridging** (PyO3, pybind11, JPype):
   - Track references across GC boundaries
   - Prevent premature collection
   - Risk: Circular references leak

2. **Explicit Lifecycle** (ErlPort, SnakeBridge):
   - Each call is stateless (or explicit instance management)
   - No cross-boundary GC coordination
   - Simpler but requires explicit cleanup

**SnakeBridge's approach** (explicit instance lifecycle) is safer for out-of-process model.

### Pattern 6: Streaming/Async

**Observed support**:
- **None**: pybind11, JPype (synchronous only)
- **Callbacks**: JSPyBridge (via proxies)
- **Streaming**: SnakeBridge (via Snakepit's gRPC)
- **Async/await**: Some Node.js bridges

**SnakeBridge's streaming is unique** among Erlang/Elixir bridges. This is a competitive advantage.

---

## Recommendations for SnakeBridge v2

### 1. Type System Redesign

**Inspiration**: PyO3's trait system + pybind11's three strategies

**Proposal**:
```elixir
defprotocol SnakeBridge.TypeConverter do
  @spec to_python(t, context :: map) :: {:ok, term} | {:error, term}
  def to_python(value, context)

  @spec from_python(term, context :: map) :: {:ok, t} | {:error, term}
  def from_python(value, context)
end

# Built-in implementations
defimpl SnakeBridge.TypeConverter, for: Integer do
  def to_python(i, _ctx), do: {:ok, i}
  def from_python(i, _ctx), do: {:ok, i}
end

# Custom implementations
defimpl SnakeBridge.TypeConverter, for: MyStruct do
  def to_python(%MyStruct{} = s, _ctx) do
    {:ok, %{__type__: "MyStruct", data: s.data}}
  end
end
```

**Benefits**:
- Extensible (users can add their own types)
- Explicit (clear conversion logic)
- Testable (can test conversions in isolation)

### 2. Integrated Stub Generation

**Inspiration**: nanobind's `__nb_signature__` + integrated stubgen

**Proposal**:
- Generate Elixir typespecs from manifests (already doing)
- **NEW**: Generate Python `.pyi` stubs from manifests
- **NEW**: Use Python introspection to validate stubs
- **NEW**: Include in package distribution

Example:
```bash
mix snakebridge.manifest.compile sympy
# → lib/snakebridge/sympy.ex (Elixir module)
# → priv/python/stubs/sympy.pyi (Python stub)
```

**Benefit**: Type checking on both sides of bridge

### 3. Hybrid Introspection

**Inspiration**: nanobind's structured signatures + SnakeBridge's manifests

**Proposal**:
```elixir
# Development: Runtime introspection
mix snakebridge.introspect numpy --output manifests/_drafts/numpy.json

# Review and curate
mix snakebridge.manifest.review numpy

# Production: Compile-time generation
config :snakebridge, mode: :compiled
mix snakebridge.manifest.compile numpy
```

**Benefits**:
- Best of both worlds
- Human-in-the-loop for curation
- Fast runtime (compiled mode)

### 4. Multiple Transfer Strategies

**Inspiration**: pybind11's three approaches + JSPyBridge proxies

**Proposal**: Manifest annotations for transfer strategy
```json
{
  "functions": [
    {
      "name": "get_large_array",
      "transfer": "copy",  // Full serialization
      "returns": {"type": "list", "element_type": "float"}
    },
    {
      "name": "get_model",
      "transfer": "proxy",  // Keep in Python, return reference
      "returns": {"type": "object", "class": "sklearn.Model"}
    },
    {
      "name": "get_config",
      "transfer": "auto",  // Decide based on size
      "returns": {"type": "dict"}
    }
  ]
}
```

**Implementation**:
- `copy`: Current behavior (serialize fully)
- `proxy`: Return opaque reference, subsequent calls use reference
- `auto`: Serialize if small, proxy if large

### 5. Structured Error Handling

**Inspiration**: PyO3's typed errors + ErlPort's detailed errors

**Proposal**:
```elixir
defmodule SnakeBridge.PythonError do
  defexception [:type, :message, :traceback, :context]

  def exception(opts) do
    %__MODULE__{
      type: opts[:type],           # "ValueError"
      message: opts[:message],     # "invalid literal"
      traceback: opts[:traceback], # Python traceback string
      context: %{
        manifest: opts[:manifest],
        function: opts[:function],
        args: opts[:args]
      }
    }
  end
end
```

**Benefit**: Better debugging, structured error matching

### 6. Async/Streaming Enhancements

**Inspiration**: SnakeBridge's existing streaming + Node.js bridges

**Current**: Streaming works, but could be better integrated

**Proposal**:
- Make streaming the default for appropriate functions
- Support async (fire-and-forget) calls
- Add progress callbacks for long-running operations

```elixir
# Streaming (current)
MyLib.generate_stream(%{prompt: "..."})
|> Stream.map(&process/1)

# Async (new)
{:ok, task_id} = MyLib.train_model_async(%{data: data})
:ok = MyLib.wait_for_task(task_id, timeout: :infinity)

# Progress (new)
MyLib.train_model(%{data: data},
  on_progress: fn progress -> IO.puts("#{progress}%") end
)
```

### 7. Performance Optimizations

**Inspiration**: nanobind's vectorcalls + compact objects

**Investigate**:
1. Can Snakepit use PEP 590 vectorcalls instead of traditional calls?
2. Can we reduce serialization overhead for common types?
3. Can we batch multiple calls in one gRPC message?
4. Can we use binary protocol instead of JSON for large data?

**Benchmark**: Before optimizing, establish baselines

### 8. Documentation as First-Class Concern

**Inspiration**: nanobind's integrated approach

**Already doing**: Manifest-based docs
**Could improve**:
- Auto-extract docstrings from Python
- Generate ExDoc-compatible docs
- Include examples in manifests
- Validate examples in CI

```json
{
  "functions": [
    {
      "name": "solve",
      "docs": "Solve algebraic equation for symbol",
      "examples": [
        {
          "input": {"expr": "x**2 - 4", "symbol": "x"},
          "output": ["2", "-2"]
        }
      ]
    }
  ]
}
```

**CI Task**: `mix snakebridge.manifest.test_examples`

---

## Architecture Decision Records

Based on prior art analysis, here are proposed ADRs for SnakeBridge v2:

### ADR-001: Maintain Out-of-Process Architecture

**Decision**: Keep Python in separate process (via Snakepit)

**Rationale**:
- Aligns with BEAM/Elixir philosophy (fault tolerance)
- Prevents Python crashes from taking down BEAM
- Enables distribution across nodes
- Sacrifices some performance for safety

**Alternatives Rejected**:
- In-process (NIF): Too risky, complex
- Embedded Python: Doesn't match Elixir model

**Inspiration**: ErlPort, Snakepit (vs. PyO3, pybind11)

---

### ADR-002: Adopt Protocol-Based Type Conversion

**Decision**: Use Elixir protocols for extensible type conversion

**Rationale**:
- Allows users to define custom type conversions
- Clear, testable conversion logic
- Aligns with Elixir idioms
- Inspired by PyO3's trait system

**Implementation**: See Recommendation #1

**Inspiration**: PyO3's `FromPyObject`/`IntoPyObject`

---

### ADR-003: Support Multiple Transfer Strategies

**Decision**: Allow copy, proxy, and auto transfer modes

**Rationale**:
- Different use cases need different strategies
- No one-size-fits-all solution
- Let users optimize per-function

**Implementation**: Manifest annotation (see Recommendation #4)

**Inspiration**: pybind11's three approaches, JSPyBridge proxies

---

### ADR-004: Integrate Stub Generation

**Decision**: Generate both Elixir typespecs AND Python `.pyi` stubs

**Rationale**:
- Type safety on both sides of bridge
- Better IDE support
- Catch errors earlier
- State-of-the-art (nanobind does this)

**Implementation**: See Recommendation #2

**Inspiration**: nanobind's integrated stubgen

---

### ADR-005: Hybrid Introspection Model

**Decision**: Runtime introspection for development, compile-time for production

**Rationale**:
- Flexibility during development (discover new libraries)
- Performance in production (no runtime overhead)
- Human curation step ensures quality

**Implementation**: See Recommendation #3

**Inspiration**: SnakeBridge manifests (already hybrid)

---

### ADR-006: Structured Error Types

**Decision**: Use structured exceptions with type, message, traceback, context

**Rationale**:
- Better debugging experience
- Pattern matching on error types
- Preserve Python context

**Implementation**: See Recommendation #5

**Inspiration**: PyO3, ErlPort error handling

---

### ADR-007: Documentation as Code

**Decision**: Treat documentation as first-class in manifests

**Rationale**:
- Single source of truth
- Auto-generated docs stay in sync
- Examples serve as tests

**Implementation**: See Recommendation #8

**Inspiration**: nanobind's structured signatures

---

## Competitive Analysis

### What SnakeBridge Does Uniquely Well

1. **Manifest-driven curation**: No other bridge has this
2. **Human-in-the-loop**: Explicit approval of exposed functions
3. **Documentation generation**: Automatic from manifests
4. **Streaming support**: Rare in bridges (only modern Node.js bridges)
5. **Elixir idioms**: Generated code is idiomatic Elixir

### Where SnakeBridge Lags

1. **Type safety**: PyO3/nanobind have compile-time guarantees
2. **Stub generation**: No Python `.pyi` stubs (yet)
3. **Performance**: In-process bridges (PyO3, nanobind) are faster
4. **Introspection richness**: JPype's full reflection is more powerful

### Strategic Positioning

**SnakeBridge should be**:
- The easiest way to use Python from Elixir
- The safest way (process isolation, manifests, testing)
- The most maintainable way (docs, types, examples)

**SnakeBridge should NOT try to be**:
- The fastest (accept performance trade-off for safety)
- The most flexible (curation is a feature, not a bug)
- A general FFI (focus on Python, do it well)

---

## Conclusion

### Key Takeaways

1. **Compile-time safety is valuable** (PyO3, pybind11, nanobind)
   - But requires compile-time knowledge of types
   - SnakeBridge's manifests are the Elixir equivalent

2. **Integrated documentation generation is critical** (nanobind)
   - External tools are afterthoughts and bitrot
   - SnakeBridge already does this; double down

3. **Multiple transfer strategies are needed** (pybind11, JSPyBridge)
   - Copy, proxy, shared memory each have use cases
   - SnakeBridge should support at least copy + proxy

4. **Process isolation is Elixir's strength** (ErlPort, Snakepit)
   - Don't sacrifice for performance
   - In-process is not the Elixir way

5. **Streaming is a competitive advantage** (SnakeBridge, modern Node bridges)
   - Keep and enhance streaming support
   - Consider async patterns

6. **Introspection enables automation** (JPype, nanobind)
   - Use Python's `inspect` module extensively
   - Auto-generate manifests as starting point
   - Human curates (don't fully automate)

### Recommended Priority

**High Priority** (v2.0):
1. Protocol-based type conversion (ADR-002)
2. Integrated stub generation (ADR-004)
3. Structured error handling (ADR-006)
4. Multiple transfer strategies (ADR-003)

**Medium Priority** (v2.1):
1. Performance optimizations (vectorcalls, batching)
2. Enhanced streaming/async patterns
3. Documentation examples as tests

**Low Priority** (v2.2+):
1. Distributed Python instances
2. Advanced proxy patterns
3. Custom serialization plugins

### Final Thought

SnakeBridge's manifest-driven approach is **unique and valuable**. The goal for v2 should be to:
- **Strengthen the strengths**: Better manifests, better docs, better curation
- **Address the weaknesses**: Add type safety, stub generation, multiple strategies
- **Learn from the best**: PyO3's type system, nanobind's integration, ErlPort's isolation

The combination of **Elixir's process model + Python's ecosystem + manifest-driven curation + automatic documentation** is a positioning that no other bridge can claim.

---

## Sources

1. [PyO3 Type Conversions](https://pyo3.rs/main/conversions/traits)
2. [pybind11 Type Conversions](https://pybind11.readthedocs.io/en/stable/advanced/cast/)
3. [pybind11_mkdoc](https://github.com/pybind/pybind11_mkdoc)
4. [pybind11-stubgen](https://github.com/pybind/pybind11/issues/2350)
5. [nanobind Documentation](https://nanobind.readthedocs.io/)
6. [nanobind Benchmarks](https://nanobind.readthedocs.io/en/latest/benchmark.html)
7. [Why nanobind?](https://nanobind.readthedocs.io/en/latest/why.html)
8. [ErlPort GitHub](https://github.com/erlport/erlport)
9. [ErlPort Documentation](http://erlport.org/docs/)
10. [JSPyBridge GitHub](https://github.com/extremeheat/JSPyBridge)
11. [node-python-bridge GitHub](https://github.com/Submersible/node-python-bridge)
12. [PyBridge (TypeScript)](https://marcjschmidt.de/pybridge)
13. [LFE py (ErlPort wrapper)](https://github.com/lfex/py)
14. [FromPyObject Rust Docs](https://docs.rs/pyo3/latest/pyo3/conversion/trait.FromPyObject.html)
15. [IntoPyObject Trait](https://pyo3.rs/main/doc/pyo3/conversion/trait.intopyobject)
16. [pybind11 GitHub](https://github.com/pybind/pybind11)
17. [nanobind GitHub](https://github.com/wjakob/nanobind)
18. [nanobind vs pybind11 Discussion](https://github.com/wjakob/nanobind/discussions/243)
