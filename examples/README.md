# SnakeBridge Examples

```
███████╗███╗   ██╗ █████╗ ██╗  ██╗███████╗██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗
██╔════╝████╗  ██║██╔══██╗██║ ██╔╝██╔════╝██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝
███████╗██╔██╗ ██║███████║█████╔╝ █████╗  ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗
╚════██║██║╚██╗██║██╔══██║██╔═██╗ ██╔══╝  ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝
███████║██║ ╚████║██║  ██║██║  ██╗███████╗██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗
╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝
```

This directory contains examples demonstrating SnakeBridge's capabilities for bridging Elixir and Python over gRPC.

## Quick Start

Run all examples:

```bash
./run_all.sh
```

Or run individual examples:

```bash
cd basic && mix run --no-start -e Demo.run
cd math_demo && mix run --no-start -e Demo.run
cd wrapper_args_example && mix run --no-start -e Demo.run
cd signature_showcase && mix run --no-start -e Demo.run
cd class_constructor_example && mix run --no-start -e Demo.run
cd streaming_example && mix run --no-start -e Demo.run
cd strict_mode_example && mix run --no-start -e Demo.run
cd python_idioms_example && mix run --no-start -e Demo.run
cd universal_ffi_example && mix run --no-start -e Demo.run
cd multi_session_example && mix run --no-start -e Demo.run
cd affinity_defaults_example && mix run --no-start -e Demo.run
# etc.
```

## Examples Overview

| Example | Description | Key Features |
|---------|-------------|--------------|
| **basic** | Core functionality demo | Math, strings, JSON, OS calls with explicit output |
| **math_demo** | Discovery APIs and runtime calls | `__functions__/0`, `__search__/1`, generated modules |
| **proof_pipeline** | Multi-step LaTeX/SymPy pipeline | Chaining multiple Python libraries |
| **types_showcase** | Python ↔ Elixir type mapping | int, float, str, list, dict, None, bool, bytes |
| **error_showcase** | ML error translation | ShapeMismatch, OutOfMemory, DtypeMismatch |
| **docs_showcase** | Documentation parsing | RST/Google/NumPy docstrings, math rendering |
| **telemetry_showcase** | Telemetry integration | Event logging, timing, metrics |
| **twenty_libraries** | 20 Python stdlib libraries | Performance demo with 40 sequential gRPC calls |
| **wrapper_args_example** | Wrapper opts and varargs | Optional kwargs, runtime flags, `__args__` |
| **signature_showcase** | Signature + arity model | Optional args, keyword-only validation, variadic fallback |
| **class_constructor_example** | Class constructors | `new/N` generation from `__init__`, method calls |
| **streaming_example** | Streaming wrappers | `*_stream` variants with callbacks |
| **bridge_client_example** | Python BridgeClient demo | ExecuteTool/ExecuteStreamingTool, chunk decoding |
| **strict_mode_example** | Strict mode verification | Manifest and generated file checks |
| **session_lifecycle_example** | Session lifecycle management | Auto-ref, SessionContext, cleanup |
| **multi_session_example** | Multiple snakes in the pit | Concurrent sessions, isolation, affinity modes under load |
| **affinity_defaults_example** | Single-pool affinity defaults | Default strictness, per-call overrides, busy-worker behavior |
| **python_idioms_example** | Python idioms bridge | Generators, context managers, callbacks |
| **protocol_integration_example** | Protocol integration | Inspect/String.Chars, Enumerable, dynamic exceptions |
| **universal_ffi_example** | Universal FFI showcase (v0.8.4+) | `SnakeBridge.call/4`, `get/3`, `method/4`, `attr/3`, `bytes/1`, auto-sessions |

## Verbose Output Format

All examples use an explicit format showing exactly what happens with each Python call:

```
┌─ Calculate square root
│
│  Elixir call:     Math.sqrt/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: sqrt
│  Arguments:       [144]
│
│  ⬇️  Response from Python (1250 µs)
│
└─ Result: {:ok, 12.0}
```

## Example Details

### basic

Demonstrates core SnakeBridge functionality with Python's standard library:
- Math operations (`math.sqrt`, `math.pow`, `math.log`)
- String operations (`len`, `upper`, `type`)
- JSON serialization (`json.dumps`, `json.loads`)
- OS operations (`os.getcwd`, `os.getenv`, `platform.system`)

### math_demo

Shows the discovery API for generated modules:
- List available functions with `Math.__functions__()`
- Search for functions with `Math.__search__("sqrt")`
- Explore generated code structure

### proof_pipeline

A real-world example using multiple Python ML libraries:
- PyLatexEnc for LaTeX parsing
- SymPy for symbolic math
- Custom verification logic

### types_showcase

Demonstrates how Python types map to Elixir:
- `int` → `integer()`
- `float` → `float()`
- `str` → `String.t()`
- `list` → `list()`
- `dict` → `map()`
- `None` → `nil`
- `bool` → `boolean()`
- Complex nested structures

### error_showcase

Shows SnakeBridge's ML error translation:
- Shape mismatch errors with tensor dimensions
- Out of memory errors with device info
- Dtype mismatch errors with conversion suggestions
- `ErrorTranslator.translate/1` usage

### docs_showcase

Demonstrates documentation parsing:
- Google-style docstrings
- NumPy-style docstrings
- Sphinx-style docstrings
- Math expression rendering (`:math:` → `$...$`)

### telemetry_showcase

Shows telemetry integration:
- Start/stop events with timing
- Error events
- Concurrent call tracking
- Aggregate metrics

### wrapper_args_example

Shows wrapper args handling:
- Optional keyword arguments via `opts`
- Runtime flags like `idempotent`
- `__args__` varargs support

### signature_showcase

Demonstrates the signature + arity model:
- Optional args via keyword opts
- Required keyword-only validation
- Variadic fallback wrappers for missing signatures
- Sanitized function names (`class` → `py_class`)
- Optional `numpy` call when `SNAKEBRIDGE_EXAMPLE_NUMPY=1`

### class_constructor_example

Demonstrates class constructors generated from `__init__`:
- `new/0` for empty constructors
- `new/2` for required args
- Optional kwargs for configuration

### streaming_example

Demonstrates streaming wrapper generation:
- `*_stream` variants with callbacks
- Runtime opts passed through `opts`

### bridge_client_example

Demonstrates Python BridgeClient usage against the Elixir BridgeServer:
- ExecuteTool and ExecuteStreamingTool via `snakebridge_client.py`
- Correlation header propagation and chunk decoding
- Enable with `SNAKEBRIDGE_BRIDGE_CLIENT=1`

### strict_mode_example

Demonstrates strict mode verification:
- Strict compile checks enabled in config
- Generated files and manifest stay in sync

### session_lifecycle_example

Demonstrates session lifecycle management:
- Auto-ref for complex objects
- SessionContext scoping for per-process sessions
- Automatic cleanup on owner exit
- Manual session release

### multi_session_example

**Multiple Snakes in the Pit** - Demonstrates running multiple isolated Python
sessions concurrently:
- Concurrent sessions with `Task.async` and different session IDs
- State isolation between sessions (objects in session A invisible to B)
- Affinity modes under load (`:hint`, `:strict_queue`, `:strict_fail_fast`) across pools
- Per-call affinity overrides on strict and hint pools
- Auto-session behavior and how affinity applies to process-scoped sessions
- Tainted preferred worker behavior (`:session_worker_unavailable`)
- Streaming calls that depend on session-bound refs
- Named sessions for logical grouping and reuse
- Parallel processing pattern with `Task.async_stream`
- Session-scoped object lifetime management

Use cases: multi-tenant apps, A/B testing, parallel workers with isolated state.

The affinity section intentionally drives a busy-worker scenario so you can see:
hint mode fallback (ref error), strict queue waiting, and strict fail-fast returning
`{:error, :worker_busy}`.

The example config (`examples/multi_session_example/config/runtime.exs`) defines
three pools with per-pool affinity modes so you can compare behaviors in a
single run.

### affinity_defaults_example

Demonstrates how affinity behaves in a single-pool configuration:
- Global default affinity via `SnakeBridge.ConfigHelper.configure_snakepit!(affinity: ...)`
- Per-call overrides (`:hint`, `:strict_queue`, `:strict_fail_fast`)
- Busy-worker scenarios with strict queue waiting and fail-fast errors

### python_idioms_example

Demonstrates Python idioms support:
- Lazy iteration over Python generators/iterators
- `with_python` macro for context managers
- Passing Elixir callbacks into Python functions

### protocol_integration_example

Demonstrates protocol integration for Python refs:
- `Inspect` and `String.Chars` for natural display/interpolation
- `Enumerable` support for `Enum.map/2` and `Enum.count/1`
- Dynamic exception creation and pattern matching

### twenty_libraries

Performance demonstration calling 20 Python standard library modules:
- 40 total calls (2 per library)
- Timing for each call
- Summary statistics (fastest, slowest, average)

Libraries used: `math`, `json`, `os`, `sys`, `platform`, `datetime`, `random`, `hashlib`, `base64`, `urllib.parse`, `re`, `collections`, `itertools`, `functools`, `string`, `textwrap`, `uuid`, `time`, `calendar`, `statistics`

### universal_ffi_example

Comprehensive showcase of Universal FFI features (v0.8.4+):
- `SnakeBridge.call/4` - Call any Python function dynamically
- `SnakeBridge.get/3` - Get module attributes
- `SnakeBridge.method/4` and `attr/3` - Call methods/get attributes on refs
- `SnakeBridge.bytes/1` - Explicit binary encoding for hashlib, crypto, etc.
- Non-string key maps (integer/tuple keys)
- Auto-session management
- Bang variants (`call!`, `get!`, `method!`, `attr!`)
- Streaming with `SnakeBridge.stream/5`

This is the canonical reference for Universal FFI usage - the "escape hatch" for calling Python without code generation.

## Requirements

- Elixir 1.14+
- Python 3.10+
- Snakepit 0.9.0+

## License

MIT - See the main repository LICENSE file.
