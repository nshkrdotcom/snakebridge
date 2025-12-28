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
cd basic && mix run -e Demo.run
cd math_demo && mix run -e Demo.run
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

### twenty_libraries

Performance demonstration calling 20 Python standard library modules:
- 40 total calls (2 per library)
- Timing for each call
- Summary statistics (fastest, slowest, average)

Libraries used: `math`, `json`, `os`, `sys`, `platform`, `datetime`, `random`, `hashlib`, `base64`, `urllib.parse`, `re`, `collections`, `itertools`, `functools`, `string`, `textwrap`, `uuid`, `time`, `calendar`, `statistics`

## Requirements

- Elixir 1.14+
- Python 3.10+
- Snakepit 0.8.0+

## License

MIT - See the main repository LICENSE file.

## Output

````bash
$ ./run_all.sh


   ███████╗███╗   ██╗ █████╗ ██╗  ██╗███████╗██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗
   ██╔════╝████╗  ██║██╔══██╗██║ ██╔╝██╔════╝██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝
   ███████╗██╔██╗ ██║███████║█████╔╝ █████╗  ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗
   ╚════██║██║╚██╗██║██╔══██║██╔═██╗ ██╔══╝  ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝
   ███████║██║ ╚████║██║  ██║██║  ██╗███████╗██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗
   ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝

                    ┌─────────────────────────────────────┐
                    │  Elixir  ←──── gRPC ────→  Python   │
                    └─────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════
                    SnakeBridge Examples Runner
═══════════════════════════════════════════════════════════════════════════

Started:  2025-12-27 10:04:21
Host:     ubuntu-dev
Elixir:   Erlang/OTP 28 [erts-16.1.1] [source] [64-bit] [smp:24:24] [ds:24:24:10] [async-threads:1] [jit:ns]
Python:   Python 3.12.3

───────────────────────────────────────────────────────────────────────────


┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 1/8: basic
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


10:04:22.742 [info] Loading 146 CA(s) from :otp store

10:04:22.747 [info] OTLP exporter successfully initialized
2025-12-27 10:04:22,941 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/basic/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:23,096 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/basic/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
[Snakepit] Restarting to apply script configuration...

10:04:23.209 [notice] Application snakepit exited: :stopped
[Snakepit] Restart cleanup complete (confirmed via :DOWN signal).
2025-12-27 10:04:23,389 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/basic/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:23,540 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/basic/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
╔═══════════════════════════════════════════════════════════╗
║           SnakeBridge Basic Demo - Explicit Calls         ║
╚═══════════════════════════════════════════════════════════╝

This demo shows exactly what happens when Elixir calls Python.
Each call displays:
  • The Elixir function being invoked
  • The Python module and function being called
  • The arguments being passed
  • The result being returned


─── SECTION 1: Basic Math Operations ───────────────────────

┌─ Calculate 2^10
│
│  Elixir call:     Math.pow/2
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: pow
│  Arguments:       [2, 10]
│

10:04:23.927 [info] Telemetry stream registered for worker default_worker_2_85

10:04:23.927 [info] Telemetry stream registered for worker default_worker_1_21
│  Response from Python (219383 us)
│
└─ Result: {:ok, 1024.0}

┌─ Calculate √144
│
│  Elixir call:     Math.sqrt/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: sqrt
│  Arguments:       [144]
│
│  Response from Python (1278 us)
│
└─ Result: {:ok, 12.0}

┌─ Calculate ln(e)
│
│  Elixir call:     Math.log/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: log
│  Arguments:       [2.718281828]
│
│  Response from Python (1124 us)
│
└─ Result: {:ok, 0.9999999998311266}

┌─ Floor of 3.7
│
│  Elixir call:     Math.floor/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: floor
│  Arguments:       [3.7]
│
│  Response from Python (920 us)
│
└─ Result: {:ok, 3.0}

┌─ Ceiling of 3.2
│
│  Elixir call:     Math.ceil/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: ceil
│  Arguments:       [3.2]
│
│  Response from Python (1066 us)
│
└─ Result: {:ok, 4.0}


─── SECTION 2: String Operations ───────────────────────────

┌─ Get string length
│
│  Elixir call:     Builtins.len/1
│  ────────────────────────────────────────────
│  Python module:   builtins
│  Python function: len
│  Arguments:       ["Hello, SnakeBridge!"]
│
│  Response from Python (1132 us)
│
└─ Result: {:ok, 19.0}

┌─ Capitalize each word
│
│  Elixir call:     String.capwords/1
│  ────────────────────────────────────────────
│  Python module:   string
│  Python function: capwords
│  Arguments:       ["hello world"]
│
│  Response from Python (1023 us)
│
└─ Result: {:ok, "Hello World"}

┌─ Get Python type of string
│
│  Elixir call:     Builtins.type/1
│  ────────────────────────────────────────────
│  Python module:   builtins
│  Python function: type
│  Arguments:       ["test"]
│
│  Response from Python (914 us)
│
└─ Result: {:ok, "<class 'str'>"}


─── SECTION 3: JSON Serialization ──────────────────────────

┌─ Serialize Elixir map to JSON string
│
│  Elixir call:     Json.dumps/1
│  ────────────────────────────────────────────
│  Python module:   json
│  Python function: dumps
│  Arguments:       [%{"features" => ["types", "docs", "telemetry"], "name" => "SnakeBridge", "version" => "0.6.0"}]
│
│  Response from Python (900 us)
│
└─ Result: {:ok, "{\"features\": [\"types\", \"docs\", \"telemetry\"], \"name\": \"SnakeBridge\", \"version\": \"0.6.0\"}"}

┌─ Parse JSON string to Elixir map
│
│  Elixir call:     Json.loads/1
│  ────────────────────────────────────────────
│  Python module:   json
│  Python function: loads
│  Arguments:       ["{\"greeting\": \"Hello from Python!\", \"numbers\": [1, 2, 3]}"]
│
│  Response from Python (1025 us)
│
└─ Result: {:ok, %{"greeting" => "Hello from Python!", "numbers" => [1, 2, 3]}}


─── SECTION 4: OS/System Operations ────────────────────────

┌─ Get Python's current working directory
│
│  Elixir call:     Os.getcwd/0
│  ────────────────────────────────────────────
│  Python module:   os
│  Python function: getcwd
│  Arguments:       (none)
│
│  Response from Python (1059 us)
│
└─ Result: {:ok, "/home/home/p/g/n/snakebridge/examples/basic/deps/snakepit/priv/python"}

┌─ Get HOME environment variable
│
│  Elixir call:     Os.getenv/1
│  ────────────────────────────────────────────
│  Python module:   os
│  Python function: getenv
│  Arguments:       ["HOME"]
│
│  Response from Python (961 us)
│
└─ Result: {:ok, "/home/home"}

┌─ Get operating system name
│
│  Elixir call:     Platform.system/0
│  ────────────────────────────────────────────
│  Python module:   platform
│  Python function: system
│  Arguments:       (none)
│
│  Response from Python (1084 us)
│
└─ Result: {:ok, "Linux"}

┌─ Get Python version
│
│  Elixir call:     Platform.python_version/0
│  ────────────────────────────────────────────
│  Python module:   platform
│  Python function: python_version
│  Arguments:       (none)
│
│  Response from Python (1168 us)
│
└─ Result: {:ok, "3.12.3"}



════════════════════════════════════════════════════════════
Demo complete! Each call above shows the full round-trip:
  Elixir → gRPC → Python → gRPC → Elixir
════════════════════════════════════════════════════════════


[Snakepit] Script execution finished. Shutting down gracefully...
[Snakepit] Shutdown complete (confirmed via :DOWN signal).

10:04:24.045 [notice] Application snakepit exited: :stopped

✓ basic completed in 3s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 2/8: math_demo
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


10:04:25.723 [info] Loading 146 CA(s) from :otp store

10:04:25.728 [info] OTLP exporter successfully initialized
2025-12-27 10:04:25,909 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/math_demo/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:26,060 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/math_demo/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
[Snakepit] Restarting to apply script configuration...
[Snakepit] Restart cleanup complete (confirmed via :DOWN signal).

10:04:26.169 [notice] Application snakepit exited: :stopped
2025-12-27 10:04:26,354 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/math_demo/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:26,503 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/math_demo/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
╔═══════════════════════════════════════════════════════════╗
║              SnakeBridge v3 Demo                          ║
╚═══════════════════════════════════════════════════════════╝

── Generated Code ──────────────────────────────────────────
  Root: /home/home/p/g/n/snakebridge/examples/math_demo/lib/snakebridge_generated
  Libraries: json, math
  Files: json.ex, math.ex

=== Math Functions ===
  cos/1: Return the cosine of x....
  sin/1: Return the sine of x....
  sqrt/1: Return the square root of x....

=== Math Search: sq ===
  sqrt (0.9): Return the square root of x....

=== Json Classes ===
  Json.Encoder.JSONEncoder: Extensible JSON encoder for Python data structures...
=== Runtime Math (Verbose) ===

┌─ Math.sqrt/1
│  Python module:   math
│  Python function: sqrt
│  Arguments:       [2]
│

10:04:26.811 [info] Telemetry stream registered for worker default_worker_2_132

10:04:26.811 [info] Telemetry stream registered for worker default_worker_1_68
└─ Result: {:ok, 1.4142135623730951}

┌─ Math.sin/1
│  Python module:   math
│  Python function: sin
│  Arguments:       [1.0]
│
└─ Result: {:ok, 0.8414709848078965}

┌─ Math.cos/1
│  Python module:   math
│  Python function: cos
│  Arguments:       [0.0]
│
└─ Result: {:ok, 1.0}


── Summary ─────────────────────────────────────────────────
  sqrt(2)      = 1.4142135623730951
  sin(1.0)     = 0.8414709848078965
  cos(0.0)     = 1.0


Done! Try `iex -S mix` to explore more.

[Snakepit] Script execution finished. Shutting down gracefully...
[Snakepit] Shutdown complete (confirmed via :DOWN signal).

10:04:26.905 [notice] Application snakepit exited: :stopped

✓ math_demo completed in 2s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 3/8: types_showcase
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


10:04:28.138 [info] Loading 146 CA(s) from :otp store

10:04:28.143 [info] OTLP exporter successfully initialized
2025-12-27 10:04:28,329 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/types_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:28,485 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/types_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
[Snakepit] Restarting to apply script configuration...
[Snakepit] Restart cleanup complete (confirmed via :DOWN signal).

10:04:28.583 [notice] Application snakepit exited: :stopped
2025-12-27 10:04:28,764 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/types_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:28,908 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/types_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
======================================================================
              SnakeBridge Types Showcase Demo
======================================================================

This demo demonstrates how data types map between Elixir and Python.
Each call shows the complete round-trip transformation:
  Elixir value -> gRPC -> Python -> gRPC -> Elixir value


--- SECTION 1: Integer -------------------------------------------

    +-- Integer type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [42])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [42]
    |

10:04:29.225 [info] Telemetry stream registered for worker default_worker_1_8706
    |  Python type:     <class 'int'>
    |  Elixir type:     integer
    |
    +-- Result: {:ok, "<class 'int'>"} (148703 us)

    +-- Large integer (arbitrary precision)
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [9999999999999999999])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [9999999999999999999]
    |
    |  Python type:     <class 'int'>
    |  Elixir type:     integer
    |
    +-- Result: {:ok, "<class 'int'>"} (1262 us)


--- SECTION 2: Float ---------------------------------------------

    +-- Float type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [3.14159])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [3.14159]
    |
    |  Python type:     <class 'float'>
    |  Elixir type:     float
    |
    +-- Result: {:ok, "<class 'float'>"} (1183 us)

    +-- Float with scientific notation
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [1.23e-10])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [1.23e-10]
    |
    |  Python type:     <class 'float'>
    |  Elixir type:     float
    |
    +-- Result: {:ok, "<class 'float'>"} (983 us)


--- SECTION 3: String --------------------------------------------

    +-- String type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", ["Hello, SnakeBridge!"])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       ["Hello, SnakeBridge!"]
    |
    |  Python type:     <class 'str'>
    |  Elixir type:     binary (String)
    |
    +-- Result: {:ok, "<class 'str'>"} (1056 us)

    +-- Unicode string with emoji
    |
    |  Elixir call:     Snakepit.call("builtins", "type", ["Hello"])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       ["Hello"]
    |
    |  Python type:     <class 'str'>
    |  Elixir type:     binary (String)
    |
    +-- Result: {:ok, "<class 'str'>"} (1014 us)


--- SECTION 4: List ----------------------------------------------

    +-- List type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [[1, 2, 3, 4, 5]])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [[1, 2, 3, 4, 5]]
    |
    |  Python type:     <class 'list'>
    |  Elixir type:     list
    |
    +-- Result: {:ok, "<class 'list'>"} (1049 us)

    +-- Mixed-type list
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [[1, "two", 3.0, true]])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [[1, "two", 3.0, true]]
    |
    |  Python type:     <class 'list'>
    |  Elixir type:     list
    |
    +-- Result: {:ok, "<class 'list'>"} (856 us)


--- SECTION 5: Dict/Map ------------------------------------------

    +-- Dict/Map type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [%{"name" => "Alice", "age" => 30}])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [%{"age" => 30, "name" => "Alice"}]
    |
    |  Python type:     <class 'dict'>
    |  Elixir type:     map
    |
    +-- Result: {:ok, "<class 'dict'>"} (911 us)

    +-- Nested dict/map
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [%{"user" => %{...}}])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [%{"user" => %{"name" => "Bob", "scores" => ~c"_W\\"}}]
    |
    |  Python type:     <class 'dict'>
    |  Elixir type:     map
    |
    +-- Result: {:ok, "<class 'dict'>"} (889 us)


--- SECTION 6: Tuple (as List) -----------------------------------

    Note: Elixir tuples must be converted to lists for gRPC/JSON transport.
          Use Tuple.to_list/1 before sending, tuple() in Python if needed.

    +-- Tuple converted to list
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [Tuple.to_list({1, 2, 3})])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [[1, 2, 3]]
    |

10:04:29.256 [info] Telemetry stream registered for worker default_worker_2_8770
    |  Python type:     <class 'list'>
    |  Elixir type:     list (from tuple)
    |
    +-- Result: {:ok, "<class 'list'>"} (987 us)


--- SECTION 7: None/nil ------------------------------------------

    +-- None/nil type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [nil])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [nil]
    |
    |  Python type:     <class 'NoneType'>
    |  Elixir type:     nil (atom)
    |
    +-- Result: {:ok, "<class 'NoneType'>"} (1093 us)


--- SECTION 8: Boolean -------------------------------------------

    +-- Boolean true
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [true])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [true]
    |
    |  Python type:     <class 'bool'>
    |  Elixir type:     boolean (atom)
    |
    +-- Result: {:ok, "<class 'bool'>"} (914 us)

    +-- Boolean false
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [false])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [false]
    |
    |  Python type:     <class 'bool'>
    |  Elixir type:     boolean (atom)
    |
    +-- Result: {:ok, "<class 'bool'>"} (898 us)


--- SECTION 9: Bytes/Binary --------------------------------------

    +-- Bytes/Binary type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [<<72, 101, 108, 108, 111>>])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       ["Hello"]
    |
    |  Python type:     <class 'str'>
    |  Elixir type:     binary
    |
    +-- Result: {:ok, "<class 'str'>"} (893 us)


--- SECTION 10: Complex Nested Structures ------------------------

    +-- Complex nested structure
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [%{...complex...}])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [%{"items" => [%{"active" => true, "id" => 1, "name" => "first"}, %{"active" => false, "id" => 2, "name" => "second"}, %{"active" => true, "id" => 3, "name" => "third"}], "metadata" => %{"count" => 3, "version" => "1.0"}, "tags" => ["elixir", "python", "interop"]}]
    |
    |  Python type:     <class 'dict'>
    |  Elixir type:     map (with nested lists and maps)
    |
    +-- Result: {:ok, "<class 'dict'>"} (1035 us)

    Additional: Demonstrate round-trip of nested data

    +-- Round-trip nested structure via json.loads(json.dumps(...))
    |
    |  Sending:         %{"items" => [%{"active" => true, "id" => 1, "name" => "first"}, %{"active" => false, "id" => 2, "name" => "second"}, %{"active" => true, "id" => 3, "name" => "third"}], "metadata" => %{"count" => 3, "version" => "1.0"}, "tags" => ["elixir", "python", "interop"]}
    |
    |  Received:        %{"items" => [%{"active" => true, "id" => 1, "name" => "first"}, %{"active" => false, "id" => 2, "name" => "second"}, %{"active" => true, "id" => 3, "name" => "third"}], "metadata" => %{"count" => 3, "version" => "1.0"}, "tags" => ["elixir", "python", "interop"]}
    |  Match:           true
    |
    +-- Result: {:ok, <data>} (1941 us)



======================================================================
                     Demo Complete!
======================================================================

Summary of Type Mappings:
  Python int      <-> Elixir integer
  Python float    <-> Elixir float
  Python str      <-> Elixir String (binary)
  Python list     <-> Elixir list
  Python dict     <-> Elixir map
  Python list     <-- Elixir tuple (convert with Tuple.to_list/1)
  Python None     <-> Elixir nil
  Python bool     <-> Elixir boolean
  Python bytes    <-> Elixir binary
  Nested structs  <-> Nested Elixir terms

Try `iex -S mix` to experiment with more types!
======================================================================


[Snakepit] Script execution finished. Shutting down gracefully...
[Snakepit] Shutdown complete (confirmed via :DOWN signal).

10:04:29.319 [notice] Application snakepit exited: :stopped

✓ types_showcase completed in 3s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 4/8: error_showcase
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


10:04:30.550 [info] Loading 146 CA(s) from :otp store

10:04:30.556 [info] OTLP exporter successfully initialized
2025-12-27 10:04:30,744 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/error_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:30,903 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/error_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
[Snakepit] Restarting to apply script configuration...
[Snakepit] Restart cleanup complete (confirmed via :DOWN signal).

10:04:31.008 [notice] Application snakepit exited: :stopped
2025-12-27 10:04:31,186 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/error_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:31,341 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/error_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
====================================================================
||           SnakeBridge ML Error Translation Demo                ||
====================================================================

This demo shows how SnakeBridge translates cryptic Python/ML errors
into structured, actionable error messages with helpful suggestions.


--- SECTION 1: Shape Mismatch Errors --------------------------

+-----------------------------------------------------------------
| Matrix Multiplication Shape Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.matmul/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: matmul
|  Arguments:       ["tensor[3x4]", "tensor[5x6]"]
|
|  Raw Python Error:
|    RuntimeError: shapes cannot be multiplied (3x4 and 5x6)
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.ShapeMismatch
|
|  Structured Error Fields:
|    operation:  :matmul
|    shape_a:    [3, 4]
|    shape_b:    [5, 6]
|    suggestion: For matrix multiplication, A columns (4) must equal B rows (5). Try: tensor.transpose(dim0, dim1) if B needs transposing
|
|  Formatted Error Message:
|    Shape mismatch in matmul
|      Shape A: [3, 4]
|      Shape B: [5, 6]
|
|    shapes cannot be multiplied (3x4 and 5x6)
|
|    Suggestion: For matrix multiplication, A columns (4) must equal B rows (5). Try: tensor.transpose(dim0, dim1) if B needs transposing
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Broadcasting Shape Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.add/2
|  --------------------------------------------
|  Python module:   numpy
|  Python function: add
|  Arguments:       ["array[10, 3]", "array[10, 5]"]
|
|  Raw Python Error:
|    RuntimeError: broadcasting cannot match shapes [10, 3] vs [10, 5]
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.ShapeMismatch
|
|  Structured Error Fields:
|    operation:  :broadcast
|    shape_a:    [10, 3]
|    shape_b:    [10, 5]
|    suggestion: Shapes differ at dimension 1. Check broadcasting rules or reshape tensors.
|
|  Formatted Error Message:
|    Shape mismatch in broadcast
|      Shape A: [10, 3]
|      Shape B: [10, 5]
|
|    broadcasting cannot match shapes
|
|    Suggestion: Shapes differ at dimension 1. Check broadcasting rules or reshape tensors.
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Elementwise Operation Dimension Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.multiply/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: mul
|  Arguments:       ["tensor[100]", "tensor[200]"]
|
|  Raw Python Error:
|    RuntimeError: size of tensor a (100) must match the size of tensor b (200)
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.ShapeMismatch
|
|  Structured Error Fields:
|    operation:  :elementwise
|    shape_a:    ~c"d"
|    shape_b:    [200]
|    suggestion: Shapes differ at dimension 0. Check broadcasting rules or reshape tensors.
|
|  Formatted Error Message:
|    Shape mismatch in elementwise
|      Shape A: ~c"d"
|      Shape B: [200]
|
|    size of tensor a (100) must match the size of tensor b (200)
|
|    Suggestion: Shapes differ at dimension 0. Check broadcasting rules or reshape tensors.
|
+-----------------------------------------------------------------


--- SECTION 2: Out of Memory Errors ---------------------------

+-----------------------------------------------------------------
| CUDA Out of Memory
+-----------------------------------------------------------------
|
|  Elixir call:     Model.forward/2
|  --------------------------------------------
|  Python module:   torch.nn
|  Python function: forward
|  Arguments:       ["model", "large_batch[1024, 3, 224, 224]"]
|
|  Raw Python Error:
|    RuntimeError: CUDA out of memory. Tried to allocate 8192 MiB (GPU 0; 16384 MiB total; 2048 MiB free)
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.OutOfMemory
|
|  Structured Error Fields:
|    device:       {:cuda, 0}
|    requested_mb: 8192
|    available_mb: 2048
|    total_mb:     16384
|    suggestions:  0 custom + defaults
|
|  Formatted Error Message:
|    GPU Out of Memory on CUDA:0
|
|    Memory Info:
|      Requested: 8192 MB
|      Available: 2048 MB
|      Total: 16384 MB
|
|    Suggestions:
|      1. Reduce batch size
|      2. Use gradient checkpointing
|      3. Enable mixed precision training
|      4. Clear cached memory
|      5. Move some operations to CPU
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Apple MPS Out of Memory
+-----------------------------------------------------------------
|
|  Elixir call:     Model.train_step/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: backward
|  Arguments:       ["loss", "model"]
|
|  Raw Python Error:
|    RuntimeError: MPS backend out of memory
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.OutOfMemory
|
|  Structured Error Fields:
|    device:       :mps
|    requested_mb: nil
|    available_mb: nil
|    total_mb:     nil
|    suggestions:  0 custom + defaults
|
|  Formatted Error Message:
|    GPU Out of Memory on Apple MPS
|
|    Suggestions:
|      1. Reduce batch size
|      2. Use gradient checkpointing
|      3. Enable mixed precision training
|      4. Clear cached memory
|      5. Move some operations to CPU
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| CPU Memory Exhaustion
+-----------------------------------------------------------------
|
|  Elixir call:     DataLoader.load_batch/1
|  --------------------------------------------
|  Python module:   torch.utils.data
|  Python function: DataLoader.__next__
|  Arguments:       ["dataloader"]
|
|  Raw Python Error:
|    RuntimeError: out of memory trying to allocate 32768 MB
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.OutOfMemory
|
|  Structured Error Fields:
|    device:       :cpu
|    requested_mb: 32768
|    available_mb: nil
|    total_mb:     nil
|    suggestions:  0 custom + defaults
|
|  Formatted Error Message:
|    GPU Out of Memory on CPU
|
|    Memory Info:
|      Requested: 32768 MB
|      Available: unknown MB
|      Total: unknown MB
|
|    Suggestions:
|      1. Reduce batch size
|      2. Use gradient checkpointing
|      3. Enable mixed precision training
|      4. Clear cached memory
|
+-----------------------------------------------------------------


--- SECTION 3: Dtype Mismatch Errors --------------------------

+-----------------------------------------------------------------
| Float32 vs Float64 Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.matmul/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: matmul
|  Arguments:       ["tensor[float32]", "tensor[float64]"]
|
|  Raw Python Error:
|    RuntimeError: expected scalar type Float but found Double
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.DtypeMismatch
|
|  Structured Error Fields:
|    expected:   :float32
|    got:        :float64
|    operation:  :matmul
|    suggestion: Convert with tensor.to(torch.float32) - note: this may lose precision
|
|  Formatted Error Message:
|    Dtype mismatch in matmul
|
|      Expected: float32
|      Got: float64
|
|    expected scalar type Float but found Double
|
|    Suggestion: Convert with tensor.to(torch.float32) - note: this may lose precision
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Float vs Integer Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.divide/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: div
|  Arguments:       ["tensor[float32]", "tensor[int64]"]
|
|  Raw Python Error:
|    RuntimeError: expected dtype torch.float32 but got torch.int64
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.DtypeMismatch
|
|  Structured Error Fields:
|    expected:   :float32
|    got:        :int64
|    operation:  :divide
|    suggestion: Convert with tensor.to(torch.float32)
|
|  Formatted Error Message:
|    Dtype mismatch in divide
|
|      Expected: float32
|      Got: int64
|
|    expected dtype torch.float32 but got torch.int64
|
|    Suggestion: Convert with tensor.to(torch.float32)
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Half Precision Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Model.forward/2
|  --------------------------------------------
|  Python module:   torch.nn
|  Python function: Linear.forward
|  Arguments:       ["input[float16]", "weights[float32]"]
|
|  Raw Python Error:
|    RuntimeError: expected scalar type Half but found Float
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.DtypeMismatch
|
|  Structured Error Fields:
|    expected:   :float16
|    got:        :float32
|    operation:  :linear
|    suggestion: Convert with tensor.to(torch.float16) - note: this may lose precision
|
|  Formatted Error Message:
|    Dtype mismatch in linear
|
|      Expected: float16
|      Got: float32
|
|    expected scalar type Half but found Float
|
|    Suggestion: Convert with tensor.to(torch.float16) - note: this may lose precision
|
+-----------------------------------------------------------------


--- SECTION 4: ErrorTranslator Direct Usage -------------------

The ErrorTranslator module provides utilities for translating
raw Python errors into structured SnakeBridge errors.

4.1 Translating a RuntimeError:
----
    Input:  %RuntimeError{message: "shapes cannot be multiplied (64x128 and 256x512)"}
    Output: %SnakeBridge.Error.ShapeMismatch{
  operation: :matmul,
  shape_a: [64, 128],
  shape_b: [256, 512],
  expected: nil,
  got: nil,
  python_traceback: nil,
  message: "shapes cannot be multiplied (64x128 and 256x512)",
  suggestion: "For matrix multiplication, A columns (128) must equal B rows (256). Try: tensor.transpose(dim0, dim1) if B needs transposing"
}

    Formatted message:
    Shape mismatch in matmul
      Shape A: [64, 128]
      Shape B: [256, 512]

    shapes cannot be multiplied (64x128 and 256x512)

    Suggestion: For matrix multiplication, A columns (128) must equal B rows (256). Try: tensor.transpose(dim0, dim1) if B needs transposing

4.2 Translating error message strings:
----
    Message: "CUDA out of memory. Tried to allocate 4096 MiB"
    Result:  SnakeBridge.Error.OutOfMemory

    Message: "expected scalar type Float but found Long"
    Result:  SnakeBridge.Error.DtypeMismatch

    Message: "size of tensor a (50) must match the size of tensor b (100)"
    Result:  SnakeBridge.Error.ShapeMismatch

4.3 Converting dtype strings:
----
    "Float" -> :float32
    "Double" -> :float64
    "torch.float32" -> :float32
    "torch.int64" -> :int64
    "Half" -> :float16

--- SECTION 5: Real Python Error Scenarios --------------------

Demonstrating actual Python calls that produce errors,
showing how try/rescue with ErrorTranslator works.

+-----------------------------------------------------------------
| Division by Zero
+-----------------------------------------------------------------
|
|  Calling Python division with zero denominator
|  --------------------------------------------
|  Python module:   operator
|  Python function: truediv
|  Arguments:       [1, 0]
|

10:04:33.438 [info] Telemetry stream registered for worker default_worker_1_21

10:04:33.438 [info] Telemetry stream registered for worker default_worker_2_85
|  Error from Python (185882 us)
|
|  Error Type: Snakepit.Error.ZeroDivisionError
|  Message: division by zero
|
|  (Standard Python error - no ML-specific translation needed)
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Type Error
+-----------------------------------------------------------------
|
|  Passing incompatible types to Python
|  --------------------------------------------
|  Python module:   operator
|  Python function: add
|  Arguments:       ["string", 42]
|
|  Error from Python (2695 us)
|
|  Error Type: Snakepit.Error.TypeError
|  Message: can only concatenate str (not "int") to str
|
|  (Standard Python error - no ML-specific translation needed)
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Attribute Error
+-----------------------------------------------------------------
|
|  Accessing non-existent attribute
|  --------------------------------------------
|  Python module:   builtins
|  Python function: getattr
|  Arguments:       ["hello", "nonexistent_method"]
|
|  Error from Python (2806 us)
|
|  Error Type: Snakepit.Error.AttributeError
|  Message: 'str' object has no attribute 'nonexistent_method'
|
|  (Standard Python error - no ML-specific translation needed)
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Successful Call (Contrast)
+-----------------------------------------------------------------
|
|  A working Python call for comparison
|  --------------------------------------------
|  Python module:   math
|  Python function: sqrt
|  Arguments:       [16]
|
|  Response from Python (2039 us)
|
|  Result: {:ok, 4.0}
|
+-----------------------------------------------------------------



====================================================================
Demo complete! Key takeaways:

  1. ShapeMismatch errors include shape info and fix suggestions
  2. OutOfMemory errors show memory stats and recovery strategies
  3. DtypeMismatch errors suggest conversion methods
  4. ErrorTranslator.translate/1 handles raw Python exceptions
  5. All errors provide actionable guidance for developers
====================================================================


[Snakepit] Script execution finished. Shutting down gracefully...
[Snakepit] Shutdown complete (confirmed via :DOWN signal).

10:04:33.540 [notice] Application snakepit exited: :stopped

✓ error_showcase completed in 4s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 5/8: docs_showcase
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


10:04:34.826 [info] Loading 146 CA(s) from :otp store

10:04:34.831 [info] OTLP exporter successfully initialized
2025-12-27 10:04:35,005 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/docs_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:35,147 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/docs_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
[Snakepit] Restarting to apply script configuration...
[Snakepit] Restart cleanup complete (confirmed via :DOWN signal).

10:04:35.249 [notice] Application snakepit exited: :stopped
2025-12-27 10:04:35,417 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/docs_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:35,556 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/docs_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
╔═══════════════════════════════════════════════════════════╗
║         SnakeBridge Documentation Showcase                ║
╚═══════════════════════════════════════════════════════════╝

This demo shows how Python docstrings are parsed and converted
to Elixir ExDoc-compatible Markdown format.


─── SECTION 1: Python Standard Library Docs ────────────────

┌─ Fetching documentation for: math.sqrt
│
│  Python function: math.sqrt
│

10:04:35.862 [info] Telemetry stream registered for worker default_worker_1_67

10:04:35.862 [info] Telemetry stream registered for worker default_worker_2_131
│  ─── RAW PYTHON DOCSTRING ───
│  str(object='') -> str
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
│  ─── PARSED STRUCTURE ───
│  %{
│    short_description: "str(object='') -> str",
│    params: [],
│    returns: nil,
│    style: :unknown
│  }
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  str(object='') -> str
│
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
└─ Documentation extracted successfully

┌─ Fetching documentation for: json.dumps
│
│  Python function: json.dumps
│
│  ─── RAW PYTHON DOCSTRING ───
│  str(object='') -> str
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
│  ─── PARSED STRUCTURE ───
│  %{
│    short_description: "str(object='') -> str",
│    params: [],
│    returns: nil,
│    style: :unknown
│  }
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  str(object='') -> str
│
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
└─ Documentation extracted successfully

┌─ Fetching documentation for: os.path.join
│
│  Python function: os.path.join
│
│  ─── RAW PYTHON DOCSTRING ───
│  str(object='') -> str
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
│  ─── PARSED STRUCTURE ───
│  %{
│    short_description: "str(object='') -> str",
│    params: [],
│    returns: nil,
│    style: :unknown
│  }
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  str(object='') -> str
│
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
└─ Documentation extracted successfully

┌─ Fetching documentation for: re.match
│
│  Python function: re.match
│
│  ─── RAW PYTHON DOCSTRING ───
│  str(object='') -> str
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
│  ─── PARSED STRUCTURE ───
│  %{
│    short_description: "str(object='') -> str",
│    params: [],
│    returns: nil,
│    style: :unknown
│  }
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  str(object='') -> str
│
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
└─ Documentation extracted successfully


─── SECTION 2: Docstring Style Detection ───────────────────

┌─ Google Style Docstring
│
│  Detected style: :google
│
│  ─── RAW DOCSTRING ───
│  Calculate the weighted average of values.
│
│  This function computes a weighted average using the provided
│  weights. If no weights are provided, all values are treated equally.
│
│  Args:
│      values (list[float]): The numeric values to average.
│      weights (list[float], optional): Weights for each value.
│          Defaults to equal weights.
│
│  Returns:
│      float: The weighted average of the input values.
│
│  Raises:
│      ValueError: If values is empty.
│      TypeError: If values contains non-numeric types.
│
│  Example:
│      >>> weighted_avg([1, 2, 3], [0.5, 0.3, 0.2])
│      1.7
│
│
│  ─── PARSED STRUCTURE ───
│  Short description: "Calculate the weighted average of values."
│  Long description: This function computes a weighted average using the provided...
│
│  Parameters (2):
│    - values : list[float]
│    - weights : list[float], optional
│
│  Returns: float - The weighted average of the input values...
│  Raises: ValueError, TypeError
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  Calculate the weighted average of values.
│
│  This function computes a weighted average using the provided
│  weights. If no weights are provided, all values are treated equally.
│
│  ## Parameters
│
│  - `values` - The numeric values to average. (type: `list(float())`)
│  - `weights` - Weights for each value. Defaults to equal weights. (type: `list(float())`)
│
│  ## Returns
│
│  Returns `float()`. The weighted average of the input values.
│
│  ## Raises
│
│  - `ArgumentError` - If values is empty.
│  - `ArgumentError` - If values contains non-numeric types.
│
│  ## Examples
│
│      iex> weighted_avg([1, 2, 3], [0.5, 0.3, 0.2])
│      1.7
│
└─ Style demo complete

┌─ NumPy Style Docstring
│
│  Detected style: :numpy
│
│  ─── RAW DOCSTRING ───
│  Compute the discrete Fourier Transform.
│
│  This function computes the one-dimensional n-point discrete
│  Fourier Transform (DFT) with the efficient Fast Fourier
│  Transform (FFT) algorithm.
│
│  Parameters
│  ----------
│  a : array_like
│      Input array, can be complex.
│  n : int, optional
│      Length of the transformed axis of the output.
│      If n is smaller than the length of the input, the input is cropped.
│  axis : int, optional
│      Axis over which to compute the FFT. Default is -1.
│
│  Returns
│  -------
│  complex ndarray
│      The truncated or zero-padded input, transformed along the axis.
│
│  Raises
│  ------
│  IndexError
│      If axis is not a valid axis of a.
│
│  Notes
│  -----
│  The formula for the DFT is :math:`A_k = \sum_{m=0}^{n-1} a_m e^{-2\pi i m k / n}`.
│
│  Examples
│  --------
│  >>> import numpy as np
│  >>> np.fft.fft([1, 2, 3, 4])
│  array([10.+0.j, -2.+2.j, -2.+0.j, -2.-2.j])
│
│
│  ─── PARSED STRUCTURE ───
│  Short description: "Compute the discrete Fourier Transform."
│  Long description: This function computes the one-dimensional n-point discrete
...
│
│  Parameters (3):
│    - a
│    - n
│    - axis
│
│  Returns: complex ndarray The truncated or zero-padded input, transformed along the axis. -
│  Raises: IndexError If axis is not a valid axis of a.
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  Compute the discrete Fourier Transform.
│
│  This function computes the one-dimensional n-point discrete
│  Fourier Transform (DFT) with the efficient Fast Fourier
│  Transform (FFT) algorithm.
│
│  ## Parameters
│
│  - `a` - array_like Input array, can be complex.
│  - `n` - int, optional Length of the transformed axis of the output. If n is smaller than the length of the input, the input is cropped.
│  - `axis` - int, optional Axis over which to compute the FFT. Default is -1.
│
│  ## Returns
│
│  Returns `complex ndarray The truncated or zero-padded input, transformed along the axis.`.
│
│  ## Raises
│
│  - `IndexError If axis is not a valid axis of a.` -
│
│  ## Examples
│
│      iex> import numpy as np
│      iex> np.fft.fft([1, 2, 3, 4])
│      array([10.+0.j, -2.+2.j, -2.+0.j, -2.-2.j])
│
│  ## Notes
│
│  The formula for the DFT is $A_k = \sum_{m=0}^{n-1} a_m e^{-2\pi i m k / n}$.
│
└─ Style demo complete

┌─ Sphinx Style Docstring
│
│  Detected style: :sphinx
│
│  ─── RAW DOCSTRING ───
│  Connect to a database and return a connection object.
│
│  This function establishes a connection to the specified database
│  using the provided credentials.
│
│  :param host: The database server hostname.
│  :type host: str
│  :param port: The port number to connect on.
│  :type port: int
│  :param username: Database username for authentication.
│  :type username: str
│  :param password: Database password for authentication.
│  :type password: str
│  :param timeout: Connection timeout in seconds.
│  :type timeout: float
│  :returns: A database connection object.
│  :rtype: Connection
│  :raises ConnectionError: If the connection cannot be established.
│  :raises AuthenticationError: If the credentials are invalid.
│
│
│  ─── PARSED STRUCTURE ───
│  Short description: "Connect to a database and return a connection object."
│  Long description: This function establishes a connection to the specified data...
│
│  Parameters (5):
│    - host
│    - port
│    - username
│    - password
│    - timeout
│
│  Returns: unspecified - A database connection object.
│  Raises: ConnectionError, AuthenticationError
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  Connect to a database and return a connection object.
│
│  This function establishes a connection to the specified database
│  using the provided credentials.
│
│  ## Parameters
│
│  - `host` - The database server hostname.
│  - `port` - The port number to connect on.
│  - `username` - Database username for authentication.
│  - `password` - Database password for authentication.
│  - `timeout` - Connection timeout in seconds.
│
│  ## Returns
│
│   A database connection object.
│
│  ## Raises
│
│  - `ConnectionError` - If the connection cannot be established.
│  - `AuthenticationError` - If the credentials are invalid.
│
└─ Style demo complete


─── SECTION 3: Math Expression Rendering ───────────────────

┌─ Inline math
│
│  ─── ORIGINAL (RST) ───
│  The quadratic formula is :math:`x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}`.
│
│  ─── RENDERED (Markdown) ───
│  The quadratic formula is $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
│
└─ Math rendering complete

┌─ Multiple inline expressions
│
│  ─── ORIGINAL (RST) ───
│  Given :math:`f(x) = x^2` and :math:`g(x) = 2x`, then :math:`(f \circ g)(x) = 4x^2`.
│
│  ─── RENDERED (Markdown) ───
│  Given $f(x) = x^2$ and $g(x) = 2x$, then $(f \circ g)(x) = 4x^2$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - f(x) = x^2
│  - g(x) = 2x
│  - (f \circ g)(x) = 4x^2
│
└─ Math rendering complete

┌─ Greek letters
│
│  ─── ORIGINAL (RST) ───
│  The circumference is :math:`C = 2\pi r` and area is :math:`A = \pi r^2`.
│
│  ─── RENDERED (Markdown) ───
│  The circumference is $C = 2\pi r$ and area is $A = \pi r^2$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - C = 2\pi r
│  - A = \pi r^2
│
└─ Math rendering complete

┌─ Summation and integrals
│
│  ─── ORIGINAL (RST) ───
│  The sum :math:`\sum_{i=1}^{n} i = \frac{n(n+1)}{2}` and integral :math:`\int_0^1 x^2 dx = \frac{1}{3}`.
│
│  ─── RENDERED (Markdown) ───
│  The sum $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$ and integral $\int_0^1 x^2 dx = \frac{1}{3}$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
│  - \int_0^1 x^2 dx = \frac{1}{3}
│
└─ Math rendering complete

┌─ Matrix notation
│
│  ─── ORIGINAL (RST) ───
│  A matrix :math:`\mathbf{A} = \begin{pmatrix} a & b \\ c & d \end{pmatrix}` has determinant :math:`|A| = ad - bc`.
│
│  ─── RENDERED (Markdown) ───
│  A matrix $\mathbf{A} = \begin{pmatrix} a & b \\ c & d \end{pmatrix}$ has determinant $|A| = ad - bc$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - \mathbf{A} = \begin{pmatrix} a & b \\ c & d \end{pmatrix}
│  - |A| = ad - bc
│
└─ Math rendering complete


════════════════════════════════════════════════════════════
Demo complete! SnakeBridge documentation features:
  - Automatic docstring style detection (Google, NumPy, Sphinx)
  - Parameter and return type extraction
  - Math expression rendering (:math:`...` -> $...$)
  - Python-to-Elixir type conversion
════════════════════════════════════════════════════════════


[Snakepit] Script execution finished. Shutting down gracefully...
[Snakepit] Shutdown complete (confirmed via :DOWN signal).

10:04:35.998 [notice] Application snakepit exited: :stopped

✓ docs_showcase completed in 3s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 6/8: telemetry_showcase
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


10:04:37.577 [info] Loading 146 CA(s) from :otp store

10:04:37.581 [info] OTLP exporter successfully initialized
2025-12-27 10:04:37,757 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:37,902 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.

10:04:37.997 [info] The function passed as a handler with ID "telemetry-showcase-handler" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4

10:04:37.998 [info] The function passed as a handler with ID "snakebridge-runtime-enricher" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[Snakepit] Restarting to apply script configuration...

10:04:38.006 [notice] Application snakepit exited: :stopped
[Snakepit] Restart cleanup complete (confirmed via :DOWN signal).
2025-12-27 10:04:38,177 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:38,328 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
================================================================================
                 SNAKEBRIDGE TELEMETRY SHOWCASE DEMO
================================================================================

This demo shows how SnakeBridge integrates with Erlang's :telemetry library.
You'll see telemetry events printed inline with each Python call.

Events captured:
  - [:snakepit, :python, :call, :start]   - When a Python call begins
  - [:snakepit, :python, :call, :stop]    - When a Python call completes
  - [:snakepit, :python, :call, :exception] - When a Python call fails

SnakeBridge also enriches these events via RuntimeForwarder:
  - [:snakebridge, :runtime, :call, :start]
  - [:snakebridge, :runtime, :call, :stop]
  - [:snakebridge, :runtime, :call, :exception]

================================================================================


================================================================================
                SECTION 1: Basic Calls with Telemetry Events
================================================================================

Each Python call emits telemetry events that we capture and display inline.
Watch for the [:snakepit, :python, :call, :start] and :stop events!


┌─ Calculate square root of 144
│
│  Elixir call:     Math.sqrt/1
│  Python module:   math
│  Arguments:       [144]

10:04:38.673 [info] Telemetry stream registered for worker default_worker_1_132

10:04:38.673 [info] Telemetry stream registered for worker default_worker_2_196
│
│  Response from Python (234918 us)
│
└─ Result: {:ok, 12.0}

┌─ Calculate sin(1.0)
│
│  Elixir call:     Math.sin/1
│  Python module:   math
│  Arguments:       [1.0]
│
│  Response from Python (1203 us)
│
└─ Result: {:ok, 0.8414709848078965}

┌─ Calculate 2^10
│
│  Elixir call:     Math.pow/2
│  Python module:   math
│  Arguments:       [2, 10]
│
│  Response from Python (1041 us)
│
└─ Result: {:ok, 1024.0}

┌─ Calculate floor of 3.7
│
│  Elixir call:     Math.floor/1
│  Python module:   math
│  Arguments:       [3.7]
│
│  Response from Python (1067 us)
│
└─ Result: {:ok, 3.0}


================================================================================
                SECTION 2: Error Events in Telemetry
================================================================================

When Python calls fail, telemetry captures the exception event.
This allows monitoring systems to track error rates and patterns.


┌─ Calculate sqrt(-1) - expected to fail!
│
│  Elixir call:     Math.sqrt/1
│  Python module:   math
│  Arguments:       [-1]
│
│  Error from Python (4279 us)
│
└─ Result: {:error, %Snakepit.Error.ValueError{message: "math domain error", context: %{"function" => "sqrt", "library" => "math", "python_module" => "math", "session_id" => "session_2_1766865878439997", "tool_name" => "snakebridge.call"}, stacktrace: ["Traceback (most recent call last):\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py\", line 453, in ExecuteTool\n    result_data = adapter.execute_tool(\n                  ^^^^^^^^^^^^^^^^^^^^^\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 584, in execute_tool\n    return func(*args, **kwargs)\n           ^^^^^^^^^^^^^^^^^^^^^\n", "ValueError: math domain error\n"], python_type: "ValueError", python_traceback: "Traceback (most recent call last):\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py\", line 453, in ExecuteTool\n    result_data = adapter.execute_tool(\n                  ^^^^^^^^^^^^^^^^^^^^^\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 584, in execute_tool\n    return func(*args, **kwargs)\n           ^^^^^^^^^^^^^^^^^^^^^\nValueError: math domain error\n"}}

┌─ Call non-existent module - expected to fail!
│
│  Elixir call:     NonExistent.foo/0
│  Python module:   this_module_does_not_exist
│  Arguments:       (none)
│
│  Error from Python (2788 us)
│
└─ Result: {:error, %Snakepit.Error.PythonException{message: "No module named 'this_module_does_not_exist'", context: %{"function" => "foo", "library" => "this_module_does_not_exist", "python_module" => "this_module_does_not_exist", "session_id" => "session_2_1766865878439997", "tool_name" => "snakebridge.call"}, stacktrace: ["Traceback (most recent call last):\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py\", line 453, in ExecuteTool\n    result_data = adapter.execute_tool(\n                  ^^^^^^^^^^^^^^^^^^^^^\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 582, in execute_tool\n    mod = _import_module(python_module)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 293, in _import_module\n    mod = importlib.import_module(module_name)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n", "  File \"/usr/lib/python3.12/importlib/__init__.py\", line 90, in import_module\n    return _bootstrap._gcd_import(name[level:], package, level)\n           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n", "  File \"<frozen importlib._bootstrap>\", line 1387, in _gcd_import\n", "  File \"<frozen importlib._bootstrap>\", line 1360, in _find_and_load\n", "  File \"<frozen importlib._bootstrap>\", line 1324, in _find_and_load_unlocked\n", "ModuleNotFoundError: No module named 'this_module_does_not_exist'\n"], python_type: "ModuleNotFoundError", python_traceback: "Traceback (most recent call last):\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py\", line 453, in ExecuteTool\n    result_data = adapter.execute_tool(\n                  ^^^^^^^^^^^^^^^^^^^^^\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 582, in execute_tool\n    mod = _import_module(python_module)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 293, in _import_module\n    mod = importlib.import_module(module_name)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n  File \"/usr/lib/python3.12/importlib/__init__.py\", line 90, in import_module\n    return _bootstrap._gcd_import(name[level:], package, level)\n           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n  File \"<frozen importlib._bootstrap>\", line 1387, in _gcd_import\n  File \"<frozen importlib._bootstrap>\", line 1360, in _find_and_load\n  File \"<frozen importlib._bootstrap>\", line 1324, in _find_and_load_unlocked\nModuleNotFoundError: No module named 'this_module_does_not_exist'\n"}}


================================================================================
                SECTION 3: Concurrent Calls with Interleaved Events
================================================================================

When multiple calls happen concurrently, telemetry events may interleave.
This demonstrates how telemetry captures the true execution order.

Starting 5 concurrent Python calls...


│
│  Waiting for all concurrent calls to complete...
│
│  [Concurrent] sqrt(100) = 10.0 (1197 us)
│  [Concurrent] sin(0) = 0.0 (2175 us)
│  [Concurrent] cos(0) = 1.0 (2365 us)
│  [Concurrent] floor(3.7) = 3.0 (3358 us)
│  [Concurrent] ceil(2.3) = 3.0 (3377 us)
│
│  All 5 concurrent calls completed!
│
└─ Concurrent execution finished


================================================================================
                          TELEMETRY METRICS SUMMARY
================================================================================

  Total calls:        0
  Successful calls:   0
  Failed calls:       0
  Error rate:         0.0%

  Total duration:     0 us
  Average duration:   0.0 us
  Min duration:       0 us
  Max duration:       0 us

  Events captured:    0

================================================================================


================================================================================
                          DEMO COMPLETE
================================================================================

What you learned:
  1. Telemetry events are emitted automatically for every Python call
  2. Events include timing measurements (duration in native units)
  3. Error events capture exception details for monitoring
  4. Concurrent calls produce interleaved events
  5. Aggregate metrics help track overall system health

To integrate telemetry in your own app:
  1. Use :telemetry.attach/4 to subscribe to events
  2. Forward metrics to your observability stack (Prometheus, Datadog, etc.)
  3. Use telemetry_metrics for aggregation

================================================================================


[Snakepit] Script execution finished. Shutting down gracefully...
[Snakepit] Shutdown complete (confirmed via :DOWN signal).

10:04:38.773 [notice] Application snakepit exited: :stopped

✓ telemetry_showcase completed in 2s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 7/8: proof_pipeline
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Python 3.12.3 is already installed
Running demo...

Python 3.12.3 is already installed

10:04:40.624 [info] Loading 146 CA(s) from :otp store

10:04:40.629 [info] OTLP exporter successfully initialized
2025-12-27 10:04:40,815 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/proof_pipeline/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:40,966 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/proof_pipeline/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
[Snakepit] Restarting to apply script configuration...
[Snakepit] Restart cleanup complete (confirmed via :DOWN signal).

10:04:41.075 [notice] Application snakepit exited: :stopped
2025-12-27 10:04:41,252 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/proof_pipeline/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:41,406 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/proof_pipeline/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
╔═══════════════════════════════════════════════════════════╗
║            ProofPipeline - SnakeBridge Demo               ║
╚═══════════════════════════════════════════════════════════╝

Input:
  prompt_latex:  "\\frac{d}{dx} x^2"
  student_latex: "2x"
  gold_latex:    "2 x"

Running live pipeline (requires Python libs installed)...

────────────────────────────────────────────────────────────

┌─ 1. PyLatexEnc.Latexwalker.LatexWalker.new/1
│  Python module:   pylatexenc.latexwalker
│  Python function: LatexWalker
│  Arguments:       ["2x"]
│

10:04:41.718 [info] Telemetry stream registered for worker default_worker_4_9732

10:04:41.718 [info] Telemetry stream registered for worker default_worker_3_9668

10:04:41.718 [info] Telemetry stream registered for worker default_worker_1_9540

10:04:41.718 [info] Telemetry stream registered for worker default_worker_2_9604
└─ Result: {:ok,
     %{"__snakebridge_ref__" => true, "library" => "pylatexenc", "python_module" => "pylatexenc.latexwalker", "ref_id" => "6834024ecea54ed18275e9c24f894cd8", "session_id" => "session_1_1766865881459448"}}

┌─ 2. PyLatexEnc.Latexwalker.LatexWalker.get_latex_nodes/1
│  Python module:   pylatexenc.latexwalker
│  Python function: get_latex_nodes
│  Arguments:       ["<walker_ref>"]
│
└─ Result: {:ok,
     "([LatexCharsNode(parsing_state=<parsing state 134043628601568>, pos=0, len=2, chars='2x')], 0, 2)"}

┌─ 3. ProofPipeline.PythonParser.parse_expr/1
│  Python module:   sympy.parsing.latex
│  Python function: parse_latex
│  Arguments:       ["2x"]
│
└─ Result: {:ok, "2*x"}

┌─ 4. Sympy.simplify/1
│  Python module:   sympy
│  Python function: simplify
│  Arguments:       ["2*x"]
│
└─ Result: {:ok, "2*x"}

┌─ 5. Sympy.latex/1
│  Python module:   sympy
│  Python function: latex
│  Arguments:       ["2*x"]
│
└─ Result: {:ok, "\\mathtt{\\text{2*x}}"}

┌─ 6. MathVerify.verify/2
│  Python module:   math_verify
│  Python function: verify
│  Arguments:       ["2 x", "\\mathtt{\\text{2*x}}"]
│
└─ Result: {:ok, 0.0}

┌─ 7. MathVerify.parse/1
│  Python module:   math_verify
│  Python function: parse
│  Arguments:       ["\\mathtt{\\text{2*x}}"]
│
└─ Result: {:ok, []}

════════════════════════════════════════════════════════════
PIPELINE COMPLETE
════════════════════════════════════════════════════════════

Final Result:
%{
  input: %{
    prompt_latex: "\\frac{d}{dx} x^2",
    student_latex: "2x",
    gold_latex: "2 x"
  },
  nodes: "([LatexCharsNode(parsing_state=<parsing state 134043628601568>, pos=0, len=2, chars='2x')], 0, 2)",
  rendered: "\\mathtt{\\text{2*x}}",
  simplified: "2*x",
  verdict: 0.0,
  parsed: [],
  normalized: "\\mathtt{\\text{2*x}}"
}

[Snakepit] Script execution finished. Shutting down gracefully...
[Snakepit] Shutdown complete (confirmed via :DOWN signal).

10:04:42.241 [notice] Application snakepit exited: :stopped

✓ proof_pipeline completed in 4s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 8/8: twenty_libraries
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


10:04:43.466 [info] Loading 146 CA(s) from :otp store

10:04:43.472 [info] OTLP exporter successfully initialized
2025-12-27 10:04:43,650 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/twenty_libraries/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:43,793 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/twenty_libraries/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
[Snakepit] Restarting to apply script configuration...
[Snakepit] Restart cleanup complete (confirmed via :DOWN signal).

10:04:43.894 [notice] Application snakepit exited: :stopped
2025-12-27 10:04:44,060 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/twenty_libraries/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.
2025-12-27 10:04:44,210 - __main__ - INFO - [corr=-] Loaded grpc_server.py from /home/home/p/g/n/snakebridge/examples/twenty_libraries/_build/dev/lib/snakepit/priv/python/grpc_server.py
[health-check] Python gRPC dependencies loaded successfully.

╔════════════════════════════════════════════════════════════╗
║  SnakeBridge: 20 Python Libraries Over gRPC               ║
╚════════════════════════════════════════════════════════════╝

Library 1/20: math

10:04:44.514 [info] Telemetry stream registered for worker default_worker_1_8770

10:04:44.514 [info] Telemetry stream registered for worker default_worker_2_8834
┌─ factorial(...)
│  Arguments: ~c"\n"
└─ Result: {:ok, 3628800.0}  (180.2140 ms)

┌─ sqrt(...)
│  Arguments: [144]
└─ Result: {:ok, 12.0}  (1.3880 ms)

Library 2/20: json
┌─ dumps(...)
│  Arguments: [%{"count" => 42, "hello" => "world"}]
└─ Result: {:ok, "{\"count\": 42, \"hello\": \"world\"}"}  (1.1960 ms)

┌─ loads(...)
│  Arguments: ["{\"parsed\": true, \"value\": 123}"]
└─ Result: {:ok, %{"parsed" => true, "value" => 123}}  (1.1730 ms)

Library 3/20: os
┌─ getcwd(...)
│  Arguments: []
└─ Result: {:ok, "/home/home/p/g/n/snakebridge/examples/twenty_libraries/d...}  (989.0000 us)

┌─ getenv(...)
│  Arguments: ["PATH"]
└─ Result: {:ok, "/home/home/.asdf/installs/erlang/28.1.1/erts-16.1.1/bin:...}  (1.0570 ms)

Library 4/20: sys
┌─ getrecursionlimit(...)
│  Arguments: []
└─ Result: {:ok, 1000.0}  (1.0080 ms)

┌─ getsizeof(...)
│  Arguments: ~c"d"
└─ Result: {:ok, 28.0}  (888.0000 us)

Library 5/20: platform
┌─ system(...)
│  Arguments: []
└─ Result: {:ok, "Linux"}  (881.0000 us)

┌─ python_version(...)
│  Arguments: []
└─ Result: {:ok, "3.12.3"}  (1.0790 ms)

Library 6/20: datetime
┌─ datetime(...)
│  Arguments: [2024, 12, 25, ...]
└─ Result: {:ok, "2024-12-25 10:30:00"}  (948.0000 us)

┌─ date(...)
│  Arguments: [2024, 1, 1]
└─ Result: {:ok, "2024-01-01"}  (917.0000 us)

Library 7/20: random
┌─ random(...)
│  Arguments: []
└─ Result: {:ok, 0.18806171751196232}  (945.0000 us)

┌─ randint(...)
│  Arguments: [1, 100]
└─ Result: {:ok, 16.0}  (941.0000 us)

Library 8/20: copy
┌─ copy(...)
│  Arguments: [[1, 2, ...]]
└─ Result: {:ok, [1, 2, 3]}  (904.0000 us)

┌─ deepcopy(...)
│  Arguments: [%{"nested" => [1, ...]}]
└─ Result: {:ok, %{"nested" => [1, 2, 3]}}  (918.0000 us)

Library 9/20: base64
┌─ b64decode(...)
│  Arguments: ["SGVsbG8sIFNuYWtlQnJpZGdlIQ=="]
└─ Result: {:ok, "b'Hello, SnakeBridge!'"}  (916.0000 us)

┌─ b64decode(...)
│  Arguments: ["SGVsbG8gV29ybGQh"]
└─ Result: {:ok, "b'Hello World!'"}  (916.0000 us)

Library 10/20: urllib_parse
┌─ quote(...)
│  Arguments: ["hello world/test"]
└─ Result: {:ok, "hello%20world/test"}  (991.0000 us)

┌─ unquote(...)
│  Arguments: ["hello%20world%2Ftest"]
└─ Result: {:ok, "hello world/test"}  (1.0900 ms)

Library 11/20: re
┌─ match(...)
│  Arguments: ["\\d+", "123abc"]
└─ Result: {:ok, "<re.Match object; span=(0, 3), match='123'>"}  (1.0570 ms)

┌─ search(...)
│  Arguments: ["[a-z]+", "123abc456"]
└─ Result: {:ok, "<re.Match object; span=(3, 6), match='abc'>"}  (1.1210 ms)

Library 12/20: collections
┌─ Counter(...)
│  Arguments: [["a", "b", ...]]
└─ Result: {:ok, %{"a" => 3, "b" => 2, "c" => 1}}  (1.0160 ms)

┌─ Counter(...)
│  Arguments: [["red", "blue", ...]]
└─ Result: {:ok, %{"blue" => 3, "green" => 1, "red" => 2}}  (931.0000 us)

Library 13/20: itertools
┌─ combinations(...)
│  Arguments: [["a", "b", ...], 2]
└─ Result: {:ok, "<itertools.combinations object at 0x795eea1bdee0>"}  (1.0360 ms)

┌─ permutations(...)
│  Arguments: [["x", "y"], 2]
└─ Result: {:ok, "<itertools.permutations object at 0x795eea1be160>"}  (870.0000 us)

Library 14/20: operator
┌─ add(...)
│  Arguments: [10, 20]
└─ Result: {:ok, 30.0}  (904.0000 us)

┌─ mul(...)
│  Arguments: [5, 7]
└─ Result: {:ok, 35.0}  (945.0000 us)

Library 15/20: string
┌─ capwords(...)
│  Arguments: ["hello world from elixir"]
└─ Result: {:ok, "Hello World From Elixir"}  (928.0000 us)

┌─ capwords(...)
│  Arguments: ["snakebridge is awesome"]
└─ Result: {:ok, "Snakebridge Is Awesome"}  (897.0000 us)

Library 16/20: textwrap
┌─ wrap(...)
│  Arguments: ["The quick brown fox jumps over the lazy dog", 20]
└─ Result: {:ok, ["The quick brown fox", "jumps over the lazy", "dog"]}  (983.0000 us)

┌─ fill(...)
│  Arguments: ["SnakeBridge enables seamless Python interop", 25]
└─ Result: {:ok, "SnakeBridge enables\nseamless Python interop"}  (960.0000 us)

Library 17/20: uuid
┌─ uuid4(...)
│  Arguments: []
└─ Result: {:ok, "b33b9f5b-7bdc-445a-aafa-12d90c4455c9"}  (1.0410 ms)

┌─ uuid4(...)
│  Arguments: []
└─ Result: {:ok, "c0eb3b79-2a5c-4ad0-9a7d-88916f713191"}  (960.0000 us)

Library 18/20: time
┌─ time(...)
│  Arguments: []
└─ Result: {:ok, 1766865884.5712693}  (978.0000 us)

┌─ ctime(...)
│  Arguments: []
└─ Result: {:ok, "Sat Dec 27 10:04:44 2025"}  (917.0000 us)

Library 19/20: calendar
┌─ isleap(...)
│  Arguments: [2024]
└─ Result: {:ok, 1.0}  (924.0000 us)

┌─ monthrange(...)
│  Arguments: [2024, 2]
└─ Result: {:ok, "(calendar.THURSDAY, 29)"}  (894.0000 us)

Library 20/20: statistics
┌─ mean(...)
│  Arguments: [[10, 20, ...]]
└─ Result: {:ok, 30.0}  (2.7010 ms)

┌─ stdev(...)
│  Arguments: [[10, 20, ...]]
└─ Result: {:ok, 15.811388300841896}  (986.0000 us)

════════════════════════════════════════════════════════════
SUMMARY
────────────────────────────────────────────────────────────
Total libraries called:  20
Total calls made:        40  (2 per library)
Successful calls:        40
Failed calls:            0
Total time:              220.4080 ms
Average per call:        5.5102 ms
Fastest:                 itertools.permutations (870.0000 us)
Slowest:                 math.factorial (180.2140 ms)
════════════════════════════════════════════════════════════


[Snakepit] Script execution finished. Shutting down gracefully...
[Snakepit] Shutdown complete (confirmed via :DOWN signal).

10:04:44.710 [notice] Application snakepit exited: :stopped

✓ twenty_libraries completed in 2s

═══════════════════════════════════════════════════════════════════════════
                           SUMMARY
═══════════════════════════════════════════════════════════════════════════

Started:   2025-12-27 10:04:21
Finished:  2025-12-27 10:04:44
Duration:  0m 23s (23 seconds)

Examples Run:
  ✓ basic (3s)
  ✓ math_demo (2s)
  ✓ types_showcase (3s)
  ✓ error_showcase (4s)
  ✓ docs_showcase (3s)
  ✓ telemetry_showcase (2s)
  ✓ proof_pipeline (4s)
  ✓ twenty_libraries (2s)

All 8 examples passed!

═══════════════════════════════════════════════════════════════════════════

   _____                      _      _       _
  / ____|                    | |    | |     | |
 | |     ___  _ __ ___  _ __ | | ___| |_ ___| |
 | |    / _ \| '_ ` _ \| '_ \| |/ _ \ __/ _ \ |
 | |___| (_) | | | | | | |_) | |  __/ ||  __/_|
  \_____\___/|_| |_| |_| .__/|_|\___|\__\___(_)
                       | |
                       |_|

home@ubuntu-dev:~/p/g/n/snakebridge/examples$ ^C
home@ubuntu-dev:~/p/g/n/snakebridge/examples$ cd ..
home@ubuntu-dev:~/p/g/n/snakebridge$ claude

╭─── Claude Code v2.0.76 ───────────────────────────────────────────────────────────────────────╮
│                           │ Tips for getting started                                          │
│       Welcome back!       │ Run /init to create a CLAUDE.md file with instructions for Claude │
│                           │ ───────────────────────────────────────────────────────────────── │
│        * ▐▛███▜▌ *        │ Recent activity                                                   │
│       * ▝▜█████▛▘ *       │ No recent activity                                                │
│        *  ▘▘ ▝▝  *        │                                                                   │
│                           │                                                                   │
│   Opus 4.5 · Claude API   │                                                                   │
│    ~/p/g/n/snakebridge    │                                                                   │
╰───────────────────────────────────────────────────────────────────────────────────────────────╯

> update the short description of the project for hex in mix.exs to reflect the current arch. keep it short enough
so it publishes

● Read(mix.exs)
  ⎿  Read 106 lines

● Read(README.md)
  ⎿  Read 196 lines

● The current description is "Generate type-safe Elixir bindings for Python libraries". Based on the README, the key architectural distinction is that SnakeBridge works at compile time (with Snakepit handling runtime). Let me update it to reflect that:

● Update(mix.exs)
  ⎿  Added 1 line, removed 1 line
      16
      17        # Docs
      18        name: "SnakeBridge",
      19 -      description: "Generate type-safe Elixir bindings for Python libraries",
      19 +      description: "Compile-time generator for type-safe Elixir bindings to Python libraries",
      20        source_url: @source_url,
      21        homepage_url: @source_url,
      22        docs: docs(),

● Updated the description from:
  - "Generate type-safe Elixir bindings for Python libraries"

  to:
  - "Compile-time generator for type-safe Elixir bindings to Python libraries"

  This emphasizes the key architectural point that SnakeBridge operates at compile time (with Snakepit handling runtime), and at 72 characters it's well within Hex's limits.

> and use gh to update the github description, might be okay as is idk but keep it lengthy and descriptive

● Bash(gh repo view nshkrdotcom/snakebridge --json description,name)
  ⎿ {
      "description": "Configuration-driven Python library integration for Elixir. Automatically generate type-safe
    Elixir modules from declarative configs with zero wrapper code. Bridge to Python ML ecosystem (DSPy, NumPy, Lan
    … +3 lines (ctrl+o to expand)


● The current description is decent but could better reflect the current architecture. Let me update it:

● Bash(gh repo edit nshkrdotcom/snakebridge --description "Compile-time Elixir code generator for Python library
      bindings. Declare Python dependencies (NumPy, SymPy, M…)
  ⎿  Error: Exit code 1
     HTTP 422: Validation Failed (https://api.github.com/repos/nshkrdotcom/snakebridge)
     description cannot be more than 350 characters

● Bash(gh repo edit nshkrdotcom/snakebridge --description "Compile-time Elixir code generator for Python library
      bindings. Declare dependencies in mix.exs, generate ty…)
  ⎿  (No content)

● Bash(gh repo view nshkrdotcom/snakebridge --json description)
  ⎿ {
      "description": "Compile-time Elixir code generator for Python library bindings. Declare dependencies in mix.e
    xs, generate type-safe modules with introspected typespecs and docs. Deterministic git-friendly output, strict
    … +2 lines (ctrl+o to expand)


● Updated GitHub description from:

  Configuration-driven Python library integration for Elixir. Automatically generate type-safe Elixir modules from declarative configs with zero wrapper code. Bridge to Python ML ecosystem (DSPy, NumPy, LangChain) with streaming support, bidirectional tools, and compile-time optimization. Built on Snakepit.

  to:

  Compile-time Elixir code generator for Python library bindings. Declare dependencies in mix.exs, generate type-safe modules with introspected typespecs and docs. Deterministic git-friendly output, strict CI mode, streaming, and custom helpers. Runtime via Snakepit.

  Key improvements:
  - Leads with "compile-time" to emphasize the architecture
  - Clarifies the relationship with Snakepit (runtime, not "built on")
  - Mentions deterministic/git-friendly output (a key feature)
  - Adds strict CI mode
  - Removed outdated "bidirectional tools" reference

^Chome@ubuntu-dev:~/p/g/n/snakebridge$ nano mix.exs
home@ubuntu-dev:~/p/g/n/snakebridge$ mix deps.get
Resolving Hex dependencies...
Resolution completed in 0.047s
Unchanged:
  acceptor_pool 1.0.1
  bunt 1.0.0
  cowboy 2.14.2
  cowboy_telemetry 0.4.0
  cowlib 2.16.0
  credo 1.7.13
  ctx 0.6.0
  dialyxir 1.4.6
  earmark_parser 1.4.44
  erlex 0.2.7
  ex_doc 0.39.1
  file_system 1.1.1
  flow 1.2.4
  gen_stage 1.3.2
  googleapis 0.1.0
  gproc 0.9.1
  grpc 0.11.5
  grpcbox 0.17.1
  gun 2.2.0
  hpack_erl 0.3.0
  hpax 1.0.3
  jason 1.4.4
  makeup 1.2.1
  mox 1.2.0
  nimble_ownership 1.0.2
  nimble_parsec 1.4.2
  opentelemetry 1.7.0
  opentelemetry_api 1.5.0
  opentelemetry_exporter 1.10.0
  opentelemetry_telemetry 1.1.2
  plug 1.19.1
  protobuf 0.15.0
  ranch 2.2.0
  ssl_verify_fun 1.1.7
  telemetry 1.3.0
home@ubuntu-dev:~/p/g/n/snakebridge$ cd examples/
home@ubuntu-dev:~/p/g/n/snakebridge/examples$ codex
╭───────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v0.77.0)                         │
│                                                   │
│ model:     gpt-5.2-codex xhigh   /model to change │
│ directory: ~/p/g/n/snakebridge/examples           │
╰───────────────────────────────────────────────────╯
› for all examples update mix.exs to snakepit 0.8.1 and do mix depsg.et and compile


• Explored
  └ List ls
    Search rg --files -g mix.exs
    Read mix.exs
    Search rg --files -g mix.exs -g '!*/deps/*'
    Search snakepit in mix.exs
    Search snakepit in mix.exs
    Search snakepit in mix.exs

• Ran for d in basic docs_showcase error_showcase math_demo proof_pipeline telemetry_showcase twenty_libraries
  │ types_showcase; do echo "==> $d"; (cd "$d" && mix deps.get && mix compile); done
  └ ==> basic
    Resolving Hex dependencies...
    … +402 lines
    ==> types_showcase
    Generated types_showcase app

• Explored
  └ Search snakepit in mix.exs
    Read mix.exs

• Ran git status --short
  └  M math_demo/config/config.exs
     M math_demo/lib/demo.ex
    … +48 lines
    ?? ../test/snakebridge/wheel_selector_test.exs
    ?? ../test/support/

• I've updated the snakepit dependency to > 0.8.1 in all example mix.exs files and ran mix deps.get and mix compile in
  each example project, which likely updated mix.lock files and generated some code. Notably, I also noticed many pre-
  existing modified and untracked files outside the example directories in the repo. How should I handle these going
  forward? Options: 1) ignore them and focus only on example changes, or 2) isolate a diff just for the example updates?

  Summarizing dependency update and build steps

  I updated the snakepit dependency to > 0.8.1 in all example mix.exs files that declare it (6 of 8 examples) and ran
  mix deps.get and mix compile across all 8 example projects, including those without the dependency like math_demo and
  proof_pipeline. This updated mix.lock files as expected. I noticed many pre-existing modified and untracked files
  outside these example changes when checking the repo status. How should I proceed with those? Options: 1) ignore them
  and focus only on example updates, or 2) isolate a patch that includes only the example changes?

─ Worked for 2m 50s ────────────────────────────────────────────────────────────────────────────────────────────────────

• Updated the :snakepit dependency to ~> 0.8.1 in every example mix.exs that declares it, then ran mix deps.get and mix
  compile across all example projects. math_demo and proof_pipeline don’t list :snakepit in their mix.exs, so there was
  nothing to edit there.

  Updated mix.exs

  - basic/mix.exs
  - docs_showcase/mix.exs
  - error_showcase/mix.exs
  - telemetry_showcase/mix.exs
  - twenty_libraries/mix.exs
  - types_showcase/mix.exs

  Commands run

  - mix deps.get + mix compile in basic, docs_showcase, error_showcase, math_demo, proof_pipeline, telemetry_showcase,
    twenty_libraries, types_showcase (this also refreshed the local mix.lock files for the snakepit upgrade).

  I noticed many pre‑existing modified/untracked files outside these changes when checking repo status. How would you
  like to proceed?

  1. Ignore them and keep focusing only on the example updates.
  2. I should isolate a patch/diff that only includes the example updates.
Token usage: total=21,350 input=14,869 (+ 96,256 cached) output=6,481 (reasoning 5,568)
To continue this session, run codex resume 019b61fa-6408-7f12-ae66-5235b97bb618
home@ubuntu-dev:~/p/g/n/snakebridge/examples$ ^C
home@ubuntu-dev:~/p/g/n/snakebridge/examples$ ./run_all.sh


   ███████╗███╗   ██╗ █████╗ ██╗  ██╗███████╗██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗
   ██╔════╝████╗  ██║██╔══██╗██║ ██╔╝██╔════╝██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝
   ███████╗██╔██╗ ██║███████║█████╔╝ █████╗  ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗
   ╚════██║██║╚██╗██║██╔══██║██╔═██╗ ██╔══╝  ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝
   ███████║██║ ╚████║██║  ██║██║  ██╗███████╗██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗
   ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝

                    ┌─────────────────────────────────────┐
                    │  Elixir  ←──── gRPC ────→  Python   │
                    └─────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════
                    SnakeBridge Examples Runner
═══════════════════════════════════════════════════════════════════════════

Started:  2025-12-27 12:46:30
Host:     ubuntu-dev
Elixir:   Erlang/OTP 28 [erts-16.1.1] [source] [64-bit] [smp:24:24] [ds:24:24:10] [async-threads:1] [jit:ns]
Python:   Python 3.12.3

───────────────────────────────────────────────────────────────────────────


┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 1/8: basic
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


12:46:32.120 [info] Loading 146 CA(s) from :otp store

12:46:32.126 [info] OTLP exporter successfully initialized

12:46:32.868 [notice] Application snakepit exited: :stopped
╔═══════════════════════════════════════════════════════════╗
║           SnakeBridge Basic Demo - Explicit Calls         ║
╚═══════════════════════════════════════════════════════════╝

This demo shows exactly what happens when Elixir calls Python.
Each call displays:
  • The Elixir function being invoked
  • The Python module and function being called
  • The arguments being passed
  • The result being returned


─── SECTION 1: Basic Math Operations ───────────────────────

┌─ Calculate 2^10
│
│  Elixir call:     Math.pow/2
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: pow
│  Arguments:       [2, 10]
│
│  Response from Python (279554 us)
│
└─ Result: {:ok, 1024.0}

┌─ Calculate √144
│
│  Elixir call:     Math.sqrt/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: sqrt
│  Arguments:       [144]
│
│  Response from Python (1909 us)
│
└─ Result: {:ok, 12.0}

┌─ Calculate ln(e)
│
│  Elixir call:     Math.log/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: log
│  Arguments:       [2.718281828]
│
│  Response from Python (1340 us)
│
└─ Result: {:ok, 0.9999999998311266}

┌─ Floor of 3.7
│
│  Elixir call:     Math.floor/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: floor
│  Arguments:       [3.7]
│
│  Response from Python (980 us)
│
└─ Result: {:ok, 3.0}

┌─ Ceiling of 3.2
│
│  Elixir call:     Math.ceil/1
│  ────────────────────────────────────────────
│  Python module:   math
│  Python function: ceil
│  Arguments:       [3.2]
│
│  Response from Python (1147 us)
│
└─ Result: {:ok, 4.0}


─── SECTION 2: String Operations ───────────────────────────

┌─ Get string length
│
│  Elixir call:     Builtins.len/1
│  ────────────────────────────────────────────
│  Python module:   builtins
│  Python function: len
│  Arguments:       ["Hello, SnakeBridge!"]
│
│  Response from Python (1454 us)
│
└─ Result: {:ok, 19.0}

┌─ Capitalize each word
│
│  Elixir call:     String.capwords/1
│  ────────────────────────────────────────────
│  Python module:   string
│  Python function: capwords
│  Arguments:       ["hello world"]
│
│  Response from Python (1255 us)
│
└─ Result: {:ok, "Hello World"}

┌─ Get Python type of string
│
│  Elixir call:     Builtins.type/1
│  ────────────────────────────────────────────
│  Python module:   builtins
│  Python function: type
│  Arguments:       ["test"]
│
│  Response from Python (998 us)
│
└─ Result: {:ok, "<class 'str'>"}


─── SECTION 3: JSON Serialization ──────────────────────────

┌─ Serialize Elixir map to JSON string
│
│  Elixir call:     Json.dumps/1
│  ────────────────────────────────────────────
│  Python module:   json
│  Python function: dumps
│  Arguments:       [%{"features" => ["types", "docs", "telemetry"], "name" => "SnakeBridge", "version" => "0.6.0"}]
│
│  Response from Python (919 us)
│
└─ Result: {:ok, "{\"features\": [\"types\", \"docs\", \"telemetry\"], \"name\": \"SnakeBridge\", \"version\": \"0.6.0\"}"}

┌─ Parse JSON string to Elixir map
│
│  Elixir call:     Json.loads/1
│  ────────────────────────────────────────────
│  Python module:   json
│  Python function: loads
│  Arguments:       ["{\"greeting\": \"Hello from Python!\", \"numbers\": [1, 2, 3]}"]
│
│  Response from Python (926 us)
│
└─ Result: {:ok, %{"greeting" => "Hello from Python!", "numbers" => [1, 2, 3]}}


─── SECTION 4: OS/System Operations ────────────────────────

┌─ Get Python's current working directory
│
│  Elixir call:     Os.getcwd/0
│  ────────────────────────────────────────────
│  Python module:   os
│  Python function: getcwd
│  Arguments:       (none)
│
│  Response from Python (862 us)
│
└─ Result: {:ok, "/home/home/p/g/n/snakebridge/examples/basic/deps/snakepit/priv/python"}

┌─ Get HOME environment variable
│
│  Elixir call:     Os.getenv/1
│  ────────────────────────────────────────────
│  Python module:   os
│  Python function: getenv
│  Arguments:       ["HOME"]
│
│  Response from Python (757 us)
│
└─ Result: {:ok, "/home/home"}

┌─ Get operating system name
│
│  Elixir call:     Platform.system/0
│  ────────────────────────────────────────────
│  Python module:   platform
│  Python function: system
│  Arguments:       (none)
│
│  Response from Python (877 us)
│
└─ Result: {:ok, "Linux"}

┌─ Get Python version
│
│  Elixir call:     Platform.python_version/0
│  ────────────────────────────────────────────
│  Python module:   platform
│  Python function: python_version
│  Arguments:       (none)
│
│  Response from Python (1066 us)
│
└─ Result: {:ok, "3.12.3"}



════════════════════════════════════════════════════════════
Demo complete! Each call above shows the full round-trip:
  Elixir → gRPC → Python → gRPC → Elixir
════════════════════════════════════════════════════════════


12:46:33.774 [notice] Application snakepit exited: :stopped

✓ basic completed in 3s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 2/8: math_demo
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


12:46:35.748 [info] Loading 146 CA(s) from :otp store

12:46:35.754 [info] OTLP exporter successfully initialized

12:46:36.329 [notice] Application snakepit exited: :stopped
╔═══════════════════════════════════════════════════════════╗
║              SnakeBridge v3 Demo                          ║
╚═══════════════════════════════════════════════════════════╝

── Generated Code ──────────────────────────────────────────
  Root: /home/home/p/g/n/snakebridge/examples/math_demo/lib/snakebridge_generated
  Libraries: json, math
  Files: json.ex, math.ex

=== Math Functions ===
  cos/1: Return the cosine of x....
  sin/1: Return the sine of x....
  sqrt/1: Return the square root of x....

=== Math Search: sq ===
  sqrt (0.9): Return the square root of x....

=== Json Classes ===
  Json.Encoder.JSONEncoder: Extensible JSON encoder for Python data structures...
=== Runtime Math (Verbose) ===

┌─ Math.sqrt/1
│  Python module:   math
│  Python function: sqrt
│  Arguments:       [2]
│
└─ Result: {:ok, 1.4142135623730951}

┌─ Math.sin/1
│  Python module:   math
│  Python function: sin
│  Arguments:       [1.0]
│
└─ Result: {:ok, 0.8414709848078965}

┌─ Math.cos/1
│  Python module:   math
│  Python function: cos
│  Arguments:       [0.0]
│
└─ Result: {:ok, 1.0}


── Summary ─────────────────────────────────────────────────
  sqrt(2)      = 1.4142135623730951
  sin(1.0)     = 0.8414709848078965
  cos(0.0)     = 1.0


Done! Try `iex -S mix` to explore more.

12:46:37.273 [notice] Application snakepit exited: :stopped

✓ math_demo completed in 4s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 3/8: types_showcase
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


12:46:38.646 [info] Loading 146 CA(s) from :otp store

12:46:38.654 [info] OTLP exporter successfully initialized

12:46:39.238 [notice] Application snakepit exited: :stopped
======================================================================
              SnakeBridge Types Showcase Demo
======================================================================

This demo demonstrates how data types map between Elixir and Python.
Each call shows the complete round-trip transformation:
  Elixir value -> gRPC -> Python -> gRPC -> Elixir value


--- SECTION 1: Integer -------------------------------------------

    +-- Integer type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [42])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [42]
    |
    |  Python type:     <class 'int'>
    |  Elixir type:     integer
    |
    +-- Result: {:ok, "<class 'int'>"} (264540 us)

    +-- Large integer (arbitrary precision)
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [9999999999999999999])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [9999999999999999999]
    |
    |  Python type:     <class 'int'>
    |  Elixir type:     integer
    |
    +-- Result: {:ok, "<class 'int'>"} (1783 us)


--- SECTION 2: Float ---------------------------------------------

    +-- Float type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [3.14159])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [3.14159]
    |
    |  Python type:     <class 'float'>
    |  Elixir type:     float
    |
    +-- Result: {:ok, "<class 'float'>"} (1488 us)

    +-- Float with scientific notation
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [1.23e-10])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [1.23e-10]
    |
    |  Python type:     <class 'float'>
    |  Elixir type:     float
    |
    +-- Result: {:ok, "<class 'float'>"} (1173 us)


--- SECTION 3: String --------------------------------------------

    +-- String type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", ["Hello, SnakeBridge!"])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       ["Hello, SnakeBridge!"]
    |
    |  Python type:     <class 'str'>
    |  Elixir type:     binary (String)
    |
    +-- Result: {:ok, "<class 'str'>"} (1130 us)

    +-- Unicode string with emoji
    |
    |  Elixir call:     Snakepit.call("builtins", "type", ["Hello"])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       ["Hello"]
    |
    |  Python type:     <class 'str'>
    |  Elixir type:     binary (String)
    |
    +-- Result: {:ok, "<class 'str'>"} (933 us)


--- SECTION 4: List ----------------------------------------------

    +-- List type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [[1, 2, 3, 4, 5]])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [[1, 2, 3, 4, 5]]
    |
    |  Python type:     <class 'list'>
    |  Elixir type:     list
    |
    +-- Result: {:ok, "<class 'list'>"} (1284 us)

    +-- Mixed-type list
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [[1, "two", 3.0, true]])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [[1, "two", 3.0, true]]
    |
    |  Python type:     <class 'list'>
    |  Elixir type:     list
    |
    +-- Result: {:ok, "<class 'list'>"} (1084 us)


--- SECTION 5: Dict/Map ------------------------------------------

    +-- Dict/Map type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [%{"name" => "Alice", "age" => 30}])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [%{"age" => 30, "name" => "Alice"}]
    |
    |  Python type:     <class 'dict'>
    |  Elixir type:     map
    |
    +-- Result: {:ok, "<class 'dict'>"} (1017 us)

    +-- Nested dict/map
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [%{"user" => %{...}}])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [%{"user" => %{"name" => "Bob", "scores" => ~c"_W\\"}}]
    |
    |  Python type:     <class 'dict'>
    |  Elixir type:     map
    |
    +-- Result: {:ok, "<class 'dict'>"} (1004 us)


--- SECTION 6: Tuple (as List) -----------------------------------

    Note: Elixir tuples must be converted to lists for gRPC/JSON transport.
          Use Tuple.to_list/1 before sending, tuple() in Python if needed.

    +-- Tuple converted to list
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [Tuple.to_list({1, 2, 3})])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [[1, 2, 3]]
    |
    |  Python type:     <class 'list'>
    |  Elixir type:     list (from tuple)
    |
    +-- Result: {:ok, "<class 'list'>"} (973 us)


--- SECTION 7: None/nil ------------------------------------------

    +-- None/nil type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [nil])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [nil]
    |
    |  Python type:     <class 'NoneType'>
    |  Elixir type:     nil (atom)
    |
    +-- Result: {:ok, "<class 'NoneType'>"} (1219 us)


--- SECTION 8: Boolean -------------------------------------------

    +-- Boolean true
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [true])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [true]
    |
    |  Python type:     <class 'bool'>
    |  Elixir type:     boolean (atom)
    |
    +-- Result: {:ok, "<class 'bool'>"} (1452 us)

    +-- Boolean false
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [false])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [false]
    |
    |  Python type:     <class 'bool'>
    |  Elixir type:     boolean (atom)
    |
    +-- Result: {:ok, "<class 'bool'>"} (1586 us)


--- SECTION 9: Bytes/Binary --------------------------------------

    +-- Bytes/Binary type mapping
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [<<72, 101, 108, 108, 111>>])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       ["Hello"]
    |
    |  Python type:     <class 'str'>
    |  Elixir type:     binary
    |
    +-- Result: {:ok, "<class 'str'>"} (1533 us)


--- SECTION 10: Complex Nested Structures ------------------------

    +-- Complex nested structure
    |
    |  Elixir call:     Snakepit.call("builtins", "type", [%{...complex...}])
    |  ------------------------------------------------
    |  Python module:   builtins
    |  Python function: type
    |  Arguments:       [%{"items" => [%{"active" => true, "id" => 1, "name" => "first"}, %{"active" => false, "id" => 2, "name" => "second"}, %{"active" => true, "id" => 3, "name" => "third"}], "metadata" => %{"count" => 3, "version" => "1.0"}, "tags" => ["elixir", "python", "interop"]}]
    |
    |  Python type:     <class 'dict'>
    |  Elixir type:     map (with nested lists and maps)
    |
    +-- Result: {:ok, "<class 'dict'>"} (1927 us)

    Additional: Demonstrate round-trip of nested data

    +-- Round-trip nested structure via json.loads(json.dumps(...))
    |
    |  Sending:         %{"items" => [%{"active" => true, "id" => 1, "name" => "first"}, %{"active" => false, "id" => 2, "name" => "second"}, %{"active" => true, "id" => 3, "name" => "third"}], "metadata" => %{"count" => 3, "version" => "1.0"}, "tags" => ["elixir", "python", "interop"]}
    |
    |  Received:        %{"items" => [%{"active" => true, "id" => 1, "name" => "first"}, %{"active" => false, "id" => 2, "name" => "second"}, %{"active" => true, "id" => 3, "name" => "third"}], "metadata" => %{"count" => 3, "version" => "1.0"}, "tags" => ["elixir", "python", "interop"]}
    |  Match:           true
    |
    +-- Result: {:ok, <data>} (3156 us)



======================================================================
                     Demo Complete!
======================================================================

Summary of Type Mappings:
  Python int      <-> Elixir integer
  Python float    <-> Elixir float
  Python str      <-> Elixir String (binary)
  Python list     <-> Elixir list
  Python dict     <-> Elixir map
  Python list     <-- Elixir tuple (convert with Tuple.to_list/1)
  Python None     <-> Elixir nil
  Python bool     <-> Elixir boolean
  Python bytes    <-> Elixir binary
  Nested structs  <-> Nested Elixir terms

Try `iex -S mix` to experiment with more types!
======================================================================


12:46:40.174 [notice] Application snakepit exited: :stopped

✓ types_showcase completed in 3s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 4/8: error_showcase
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


12:46:41.470 [info] Loading 146 CA(s) from :otp store

12:46:41.476 [info] OTLP exporter successfully initialized

12:46:41.962 [notice] Application snakepit exited: :stopped
====================================================================
||           SnakeBridge ML Error Translation Demo                ||
====================================================================

This demo shows how SnakeBridge translates cryptic Python/ML errors
into structured, actionable error messages with helpful suggestions.


--- SECTION 1: Shape Mismatch Errors --------------------------

+-----------------------------------------------------------------
| Matrix Multiplication Shape Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.matmul/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: matmul
|  Arguments:       ["tensor[3x4]", "tensor[5x6]"]
|
|  Raw Python Error:
|    RuntimeError: shapes cannot be multiplied (3x4 and 5x6)
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.ShapeMismatch
|
|  Structured Error Fields:
|    operation:  :matmul
|    shape_a:    [3, 4]
|    shape_b:    [5, 6]
|    suggestion: For matrix multiplication, A columns (4) must equal B rows (5). Try: tensor.transpose(dim0, dim1) if B needs transposing
|
|  Formatted Error Message:
|    Shape mismatch in matmul
|      Shape A: [3, 4]
|      Shape B: [5, 6]
|
|    shapes cannot be multiplied (3x4 and 5x6)
|
|    Suggestion: For matrix multiplication, A columns (4) must equal B rows (5). Try: tensor.transpose(dim0, dim1) if B needs transposing
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Broadcasting Shape Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.add/2
|  --------------------------------------------
|  Python module:   numpy
|  Python function: add
|  Arguments:       ["array[10, 3]", "array[10, 5]"]
|
|  Raw Python Error:
|    RuntimeError: broadcasting cannot match shapes [10, 3] vs [10, 5]
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.ShapeMismatch
|
|  Structured Error Fields:
|    operation:  :broadcast
|    shape_a:    [10, 3]
|    shape_b:    [10, 5]
|    suggestion: Shapes differ at dimension 1. Check broadcasting rules or reshape tensors.
|
|  Formatted Error Message:
|    Shape mismatch in broadcast
|      Shape A: [10, 3]
|      Shape B: [10, 5]
|
|    broadcasting cannot match shapes
|
|    Suggestion: Shapes differ at dimension 1. Check broadcasting rules or reshape tensors.
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Elementwise Operation Dimension Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.multiply/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: mul
|  Arguments:       ["tensor[100]", "tensor[200]"]
|
|  Raw Python Error:
|    RuntimeError: size of tensor a (100) must match the size of tensor b (200)
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.ShapeMismatch
|
|  Structured Error Fields:
|    operation:  :elementwise
|    shape_a:    ~c"d"
|    shape_b:    [200]
|    suggestion: Shapes differ at dimension 0. Check broadcasting rules or reshape tensors.
|
|  Formatted Error Message:
|    Shape mismatch in elementwise
|      Shape A: ~c"d"
|      Shape B: [200]
|
|    size of tensor a (100) must match the size of tensor b (200)
|
|    Suggestion: Shapes differ at dimension 0. Check broadcasting rules or reshape tensors.
|
+-----------------------------------------------------------------


--- SECTION 2: Out of Memory Errors ---------------------------

+-----------------------------------------------------------------
| CUDA Out of Memory
+-----------------------------------------------------------------
|
|  Elixir call:     Model.forward/2
|  --------------------------------------------
|  Python module:   torch.nn
|  Python function: forward
|  Arguments:       ["model", "large_batch[1024, 3, 224, 224]"]
|
|  Raw Python Error:
|    RuntimeError: CUDA out of memory. Tried to allocate 8192 MiB (GPU 0; 16384 MiB total; 2048 MiB free)
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.OutOfMemory
|
|  Structured Error Fields:
|    device:       {:cuda, 0}
|    requested_mb: 8192
|    available_mb: 2048
|    total_mb:     16384
|    suggestions:  0 custom + defaults
|
|  Formatted Error Message:
|    GPU Out of Memory on CUDA:0
|
|    Memory Info:
|      Requested: 8192 MB
|      Available: 2048 MB
|      Total: 16384 MB
|
|    Suggestions:
|      1. Reduce batch size
|      2. Use gradient checkpointing
|      3. Enable mixed precision training
|      4. Clear cached memory
|      5. Move some operations to CPU
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Apple MPS Out of Memory
+-----------------------------------------------------------------
|
|  Elixir call:     Model.train_step/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: backward
|  Arguments:       ["loss", "model"]
|
|  Raw Python Error:
|    RuntimeError: MPS backend out of memory
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.OutOfMemory
|
|  Structured Error Fields:
|    device:       :mps
|    requested_mb: nil
|    available_mb: nil
|    total_mb:     nil
|    suggestions:  0 custom + defaults
|
|  Formatted Error Message:
|    GPU Out of Memory on Apple MPS
|
|    Suggestions:
|      1. Reduce batch size
|      2. Use gradient checkpointing
|      3. Enable mixed precision training
|      4. Clear cached memory
|      5. Move some operations to CPU
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| CPU Memory Exhaustion
+-----------------------------------------------------------------
|
|  Elixir call:     DataLoader.load_batch/1
|  --------------------------------------------
|  Python module:   torch.utils.data
|  Python function: DataLoader.__next__
|  Arguments:       ["dataloader"]
|
|  Raw Python Error:
|    RuntimeError: out of memory trying to allocate 32768 MB
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.OutOfMemory
|
|  Structured Error Fields:
|    device:       :cpu
|    requested_mb: 32768
|    available_mb: nil
|    total_mb:     nil
|    suggestions:  0 custom + defaults
|
|  Formatted Error Message:
|    GPU Out of Memory on CPU
|
|    Memory Info:
|      Requested: 32768 MB
|      Available: unknown MB
|      Total: unknown MB
|
|    Suggestions:
|      1. Reduce batch size
|      2. Use gradient checkpointing
|      3. Enable mixed precision training
|      4. Clear cached memory
|
+-----------------------------------------------------------------


--- SECTION 3: Dtype Mismatch Errors --------------------------

+-----------------------------------------------------------------
| Float32 vs Float64 Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.matmul/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: matmul
|  Arguments:       ["tensor[float32]", "tensor[float64]"]
|
|  Raw Python Error:
|    RuntimeError: expected scalar type Float but found Double
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.DtypeMismatch
|
|  Structured Error Fields:
|    expected:   :float32
|    got:        :float64
|    operation:  :matmul
|    suggestion: Convert with tensor.to(torch.float32) - note: this may lose precision
|
|  Formatted Error Message:
|    Dtype mismatch in matmul
|
|      Expected: float32
|      Got: float64
|
|    expected scalar type Float but found Double
|
|    Suggestion: Convert with tensor.to(torch.float32) - note: this may lose precision
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Float vs Integer Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Tensor.divide/2
|  --------------------------------------------
|  Python module:   torch
|  Python function: div
|  Arguments:       ["tensor[float32]", "tensor[int64]"]
|
|  Raw Python Error:
|    RuntimeError: expected dtype torch.float32 but got torch.int64
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.DtypeMismatch
|
|  Structured Error Fields:
|    expected:   :float32
|    got:        :int64
|    operation:  :divide
|    suggestion: Convert with tensor.to(torch.float32)
|
|  Formatted Error Message:
|    Dtype mismatch in divide
|
|      Expected: float32
|      Got: int64
|
|    expected dtype torch.float32 but got torch.int64
|
|    Suggestion: Convert with tensor.to(torch.float32)
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Half Precision Mismatch
+-----------------------------------------------------------------
|
|  Elixir call:     Model.forward/2
|  --------------------------------------------
|  Python module:   torch.nn
|  Python function: Linear.forward
|  Arguments:       ["input[float16]", "weights[float32]"]
|
|  Raw Python Error:
|    RuntimeError: expected scalar type Half but found Float
|
|  SnakeBridge Translation:
|    Error Type: SnakeBridge.Error.DtypeMismatch
|
|  Structured Error Fields:
|    expected:   :float16
|    got:        :float32
|    operation:  :linear
|    suggestion: Convert with tensor.to(torch.float16) - note: this may lose precision
|
|  Formatted Error Message:
|    Dtype mismatch in linear
|
|      Expected: float16
|      Got: float32
|
|    expected scalar type Half but found Float
|
|    Suggestion: Convert with tensor.to(torch.float16) - note: this may lose precision
|
+-----------------------------------------------------------------


--- SECTION 4: ErrorTranslator Direct Usage -------------------

The ErrorTranslator module provides utilities for translating
raw Python errors into structured SnakeBridge errors.

4.1 Translating a RuntimeError:
----
    Input:  %RuntimeError{message: "shapes cannot be multiplied (64x128 and 256x512)"}
    Output: %SnakeBridge.Error.ShapeMismatch{
  operation: :matmul,
  shape_a: [64, 128],
  shape_b: [256, 512],
  expected: nil,
  got: nil,
  python_traceback: nil,
  message: "shapes cannot be multiplied (64x128 and 256x512)",
  suggestion: "For matrix multiplication, A columns (128) must equal B rows (256). Try: tensor.transpose(dim0, dim1) if B needs transposing"
}

    Formatted message:
    Shape mismatch in matmul
      Shape A: [64, 128]
      Shape B: [256, 512]

    shapes cannot be multiplied (64x128 and 256x512)

    Suggestion: For matrix multiplication, A columns (128) must equal B rows (256). Try: tensor.transpose(dim0, dim1) if B needs transposing

4.2 Translating error message strings:
----
    Message: "CUDA out of memory. Tried to allocate 4096 MiB"
    Result:  SnakeBridge.Error.OutOfMemory

    Message: "expected scalar type Float but found Long"
    Result:  SnakeBridge.Error.DtypeMismatch

    Message: "size of tensor a (50) must match the size of tensor b (100)"
    Result:  SnakeBridge.Error.ShapeMismatch

4.3 Converting dtype strings:
----
    "Float" -> :float32
    "Double" -> :float64
    "torch.float32" -> :float32
    "torch.int64" -> :int64
    "Half" -> :float16

--- SECTION 5: Real Python Error Scenarios --------------------

Demonstrating actual Python calls that produce errors,
showing how try/rescue with ErrorTranslator works.

+-----------------------------------------------------------------
| Division by Zero
+-----------------------------------------------------------------
|
|  Calling Python division with zero denominator
|  --------------------------------------------
|  Python module:   operator
|  Python function: truediv
|  Arguments:       [1, 0]
|
|  Error from Python (254211 us)
|
|  Error Type: Snakepit.Error.ZeroDivisionError
|  Message: division by zero
|
|  (Standard Python error - no ML-specific translation needed)
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Type Error
+-----------------------------------------------------------------
|
|  Passing incompatible types to Python
|  --------------------------------------------
|  Python module:   operator
|  Python function: add
|  Arguments:       ["string", 42]
|
|  Error from Python (2818 us)
|
|  Error Type: Snakepit.Error.TypeError
|  Message: can only concatenate str (not "int") to str
|
|  (Standard Python error - no ML-specific translation needed)
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Attribute Error
+-----------------------------------------------------------------
|
|  Accessing non-existent attribute
|  --------------------------------------------
|  Python module:   builtins
|  Python function: getattr
|  Arguments:       ["hello", "nonexistent_method"]
|
|  Error from Python (3106 us)
|
|  Error Type: Snakepit.Error.AttributeError
|  Message: 'str' object has no attribute 'nonexistent_method'
|
|  (Standard Python error - no ML-specific translation needed)
|
+-----------------------------------------------------------------

+-----------------------------------------------------------------
| Successful Call (Contrast)
+-----------------------------------------------------------------
|
|  A working Python call for comparison
|  --------------------------------------------
|  Python module:   math
|  Python function: sqrt
|  Arguments:       [16]
|
|  Response from Python (2374 us)
|
|  Result: {:ok, 4.0}
|
+-----------------------------------------------------------------



====================================================================
Demo complete! Key takeaways:

  1. ShapeMismatch errors include shape info and fix suggestions
  2. OutOfMemory errors show memory stats and recovery strategies
  3. DtypeMismatch errors suggest conversion methods
  4. ErrorTranslator.translate/1 handles raw Python exceptions
  5. All errors provide actionable guidance for developers
====================================================================


12:46:42.799 [notice] Application snakepit exited: :stopped

✓ error_showcase completed in 2s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 5/8: docs_showcase
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


12:46:44.078 [info] Loading 146 CA(s) from :otp store

12:46:44.083 [info] OTLP exporter successfully initialized

12:46:44.555 [notice] Application snakepit exited: :stopped
╔═══════════════════════════════════════════════════════════╗
║         SnakeBridge Documentation Showcase                ║
╚═══════════════════════════════════════════════════════════╝

This demo shows how Python docstrings are parsed and converted
to Elixir ExDoc-compatible Markdown format.


─── SECTION 1: Python Standard Library Docs ────────────────

┌─ Fetching documentation for: math.sqrt
│
│  Python function: math.sqrt
│
│  ─── RAW PYTHON DOCSTRING ───
│  str(object='') -> str
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
│  ─── PARSED STRUCTURE ───
│  %{
│    short_description: "str(object='') -> str",
│    params: [],
│    returns: nil,
│    style: :unknown
│  }
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  str(object='') -> str
│
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
└─ Documentation extracted successfully

┌─ Fetching documentation for: json.dumps
│
│  Python function: json.dumps
│
│  ─── RAW PYTHON DOCSTRING ───
│  str(object='') -> str
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
│  ─── PARSED STRUCTURE ───
│  %{
│    short_description: "str(object='') -> str",
│    params: [],
│    returns: nil,
│    style: :unknown
│  }
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  str(object='') -> str
│
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
└─ Documentation extracted successfully

┌─ Fetching documentation for: os.path.join
│
│  Python function: os.path.join
│
│  ─── RAW PYTHON DOCSTRING ───
│  str(object='') -> str
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
│  ─── PARSED STRUCTURE ───
│  %{
│    short_description: "str(object='') -> str",
│    params: [],
│    returns: nil,
│    style: :unknown
│  }
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  str(object='') -> str
│
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
└─ Documentation extracted successfully

┌─ Fetching documentation for: re.match
│
│  Python function: re.match
│
│  ─── RAW PYTHON DOCSTRING ───
│  str(object='') -> str
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
│  ─── PARSED STRUCTURE ───
│  %{
│    short_description: "str(object='') -> str",
│    params: [],
│    returns: nil,
│    style: :unknown
│  }
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  str(object='') -> str
│
│  str(bytes_or_buffer[, encoding[, errors]]) -> str
│
│  Create a new string object from the given object. If encoding or
│  errors is specified, then the object must expose a data buffer
│  that will be decoded using the given encoding and error handler.
│  Otherwise, returns the result of object.__str__() (if defined)
│  or repr(object).
│  encoding defaults to sys.getdefaultencoding().
│  errors defaults to 'strict'.
│
└─ Documentation extracted successfully


─── SECTION 2: Docstring Style Detection ───────────────────

┌─ Google Style Docstring
│
│  Detected style: :google
│
│  ─── RAW DOCSTRING ───
│  Calculate the weighted average of values.
│
│  This function computes a weighted average using the provided
│  weights. If no weights are provided, all values are treated equally.
│
│  Args:
│      values (list[float]): The numeric values to average.
│      weights (list[float], optional): Weights for each value.
│          Defaults to equal weights.
│
│  Returns:
│      float: The weighted average of the input values.
│
│  Raises:
│      ValueError: If values is empty.
│      TypeError: If values contains non-numeric types.
│
│  Example:
│      >>> weighted_avg([1, 2, 3], [0.5, 0.3, 0.2])
│      1.7
│
│
│  ─── PARSED STRUCTURE ───
│  Short description: "Calculate the weighted average of values."
│  Long description: This function computes a weighted average using the provided...
│
│  Parameters (2):
│    - values : list[float]
│    - weights : list[float], optional
│
│  Returns: float - The weighted average of the input values...
│  Raises: ValueError, TypeError
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  Calculate the weighted average of values.
│
│  This function computes a weighted average using the provided
│  weights. If no weights are provided, all values are treated equally.
│
│  ## Parameters
│
│  - `values` - The numeric values to average. (type: `list(float())`)
│  - `weights` - Weights for each value. Defaults to equal weights. (type: `list(float())`)
│
│  ## Returns
│
│  Returns `float()`. The weighted average of the input values.
│
│  ## Raises
│
│  - `ArgumentError` - If values is empty.
│  - `ArgumentError` - If values contains non-numeric types.
│
│  ## Examples
│
│      iex> weighted_avg([1, 2, 3], [0.5, 0.3, 0.2])
│      1.7
│
└─ Style demo complete

┌─ NumPy Style Docstring
│
│  Detected style: :numpy
│
│  ─── RAW DOCSTRING ───
│  Compute the discrete Fourier Transform.
│
│  This function computes the one-dimensional n-point discrete
│  Fourier Transform (DFT) with the efficient Fast Fourier
│  Transform (FFT) algorithm.
│
│  Parameters
│  ----------
│  a : array_like
│      Input array, can be complex.
│  n : int, optional
│      Length of the transformed axis of the output.
│      If n is smaller than the length of the input, the input is cropped.
│  axis : int, optional
│      Axis over which to compute the FFT. Default is -1.
│
│  Returns
│  -------
│  complex ndarray
│      The truncated or zero-padded input, transformed along the axis.
│
│  Raises
│  ------
│  IndexError
│      If axis is not a valid axis of a.
│
│  Notes
│  -----
│  The formula for the DFT is :math:`A_k = \sum_{m=0}^{n-1} a_m e^{-2\pi i m k / n}`.
│
│  Examples
│  --------
│  >>> import numpy as np
│  >>> np.fft.fft([1, 2, 3, 4])
│  array([10.+0.j, -2.+2.j, -2.+0.j, -2.-2.j])
│
│
│  ─── PARSED STRUCTURE ───
│  Short description: "Compute the discrete Fourier Transform."
│  Long description: This function computes the one-dimensional n-point discrete
...
│
│  Parameters (3):
│    - a
│    - n
│    - axis
│
│  Returns: complex ndarray The truncated or zero-padded input, transformed along the axis. -
│  Raises: IndexError If axis is not a valid axis of a.
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  Compute the discrete Fourier Transform.
│
│  This function computes the one-dimensional n-point discrete
│  Fourier Transform (DFT) with the efficient Fast Fourier
│  Transform (FFT) algorithm.
│
│  ## Parameters
│
│  - `a` - array_like Input array, can be complex.
│  - `n` - int, optional Length of the transformed axis of the output. If n is smaller than the length of the input, the input is cropped.
│  - `axis` - int, optional Axis over which to compute the FFT. Default is -1.
│
│  ## Returns
│
│  Returns `complex ndarray The truncated or zero-padded input, transformed along the axis.`.
│
│  ## Raises
│
│  - `IndexError If axis is not a valid axis of a.` -
│
│  ## Examples
│
│      iex> import numpy as np
│      iex> np.fft.fft([1, 2, 3, 4])
│      array([10.+0.j, -2.+2.j, -2.+0.j, -2.-2.j])
│
│  ## Notes
│
│  The formula for the DFT is $A_k = \sum_{m=0}^{n-1} a_m e^{-2\pi i m k / n}$.
│
└─ Style demo complete

┌─ Sphinx Style Docstring
│
│  Detected style: :sphinx
│
│  ─── RAW DOCSTRING ───
│  Connect to a database and return a connection object.
│
│  This function establishes a connection to the specified database
│  using the provided credentials.
│
│  :param host: The database server hostname.
│  :type host: str
│  :param port: The port number to connect on.
│  :type port: int
│  :param username: Database username for authentication.
│  :type username: str
│  :param password: Database password for authentication.
│  :type password: str
│  :param timeout: Connection timeout in seconds.
│  :type timeout: float
│  :returns: A database connection object.
│  :rtype: Connection
│  :raises ConnectionError: If the connection cannot be established.
│  :raises AuthenticationError: If the credentials are invalid.
│
│
│  ─── PARSED STRUCTURE ───
│  Short description: "Connect to a database and return a connection object."
│  Long description: This function establishes a connection to the specified data...
│
│  Parameters (5):
│    - host
│    - port
│    - username
│    - password
│    - timeout
│
│  Returns: unspecified - A database connection object.
│  Raises: ConnectionError, AuthenticationError
│
│  ─── RENDERED ELIXIR MARKDOWN ───
│  Connect to a database and return a connection object.
│
│  This function establishes a connection to the specified database
│  using the provided credentials.
│
│  ## Parameters
│
│  - `host` - The database server hostname.
│  - `port` - The port number to connect on.
│  - `username` - Database username for authentication.
│  - `password` - Database password for authentication.
│  - `timeout` - Connection timeout in seconds.
│
│  ## Returns
│
│   A database connection object.
│
│  ## Raises
│
│  - `ConnectionError` - If the connection cannot be established.
│  - `AuthenticationError` - If the credentials are invalid.
│
└─ Style demo complete


─── SECTION 3: Math Expression Rendering ───────────────────

┌─ Inline math
│
│  ─── ORIGINAL (RST) ───
│  The quadratic formula is :math:`x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}`.
│
│  ─── RENDERED (Markdown) ───
│  The quadratic formula is $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
│
└─ Math rendering complete

┌─ Multiple inline expressions
│
│  ─── ORIGINAL (RST) ───
│  Given :math:`f(x) = x^2` and :math:`g(x) = 2x`, then :math:`(f \circ g)(x) = 4x^2`.
│
│  ─── RENDERED (Markdown) ───
│  Given $f(x) = x^2$ and $g(x) = 2x$, then $(f \circ g)(x) = 4x^2$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - f(x) = x^2
│  - g(x) = 2x
│  - (f \circ g)(x) = 4x^2
│
└─ Math rendering complete

┌─ Greek letters
│
│  ─── ORIGINAL (RST) ───
│  The circumference is :math:`C = 2\pi r` and area is :math:`A = \pi r^2`.
│
│  ─── RENDERED (Markdown) ───
│  The circumference is $C = 2\pi r$ and area is $A = \pi r^2$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - C = 2\pi r
│  - A = \pi r^2
│
└─ Math rendering complete

┌─ Summation and integrals
│
│  ─── ORIGINAL (RST) ───
│  The sum :math:`\sum_{i=1}^{n} i = \frac{n(n+1)}{2}` and integral :math:`\int_0^1 x^2 dx = \frac{1}{3}`.
│
│  ─── RENDERED (Markdown) ───
│  The sum $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$ and integral $\int_0^1 x^2 dx = \frac{1}{3}$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
│  - \int_0^1 x^2 dx = \frac{1}{3}
│
└─ Math rendering complete

┌─ Matrix notation
│
│  ─── ORIGINAL (RST) ───
│  A matrix :math:`\mathbf{A} = \begin{pmatrix} a & b \\ c & d \end{pmatrix}` has determinant :math:`|A| = ad - bc`.
│
│  ─── RENDERED (Markdown) ───
│  A matrix $\mathbf{A} = \begin{pmatrix} a & b \\ c & d \end{pmatrix}$ has determinant $|A| = ad - bc$.
│
│  ─── EXTRACTED EXPRESSIONS ───
│  - \mathbf{A} = \begin{pmatrix} a & b \\ c & d \end{pmatrix}
│  - |A| = ad - bc
│
└─ Math rendering complete


════════════════════════════════════════════════════════════
Demo complete! SnakeBridge documentation features:
  - Automatic docstring style detection (Google, NumPy, Sphinx)
  - Parameter and return type extraction
  - Math expression rendering (:math:`...` -> $...$)
  - Python-to-Elixir type conversion
════════════════════════════════════════════════════════════


12:46:45.425 [notice] Application snakepit exited: :stopped

✓ docs_showcase completed in 3s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 6/8: telemetry_showcase
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


12:46:47.180 [info] Loading 146 CA(s) from :otp store

12:46:47.185 [info] OTLP exporter successfully initialized

12:46:47.651 [info] The function passed as a handler with ID "telemetry-showcase-handler" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4

12:46:47.653 [info] The function passed as a handler with ID "snakebridge-runtime-enricher" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4

12:46:47.664 [notice] Application snakepit exited: :stopped
================================================================================
                 SNAKEBRIDGE TELEMETRY SHOWCASE DEMO
================================================================================

This demo shows how SnakeBridge integrates with Erlang's :telemetry library.
You'll see telemetry events printed inline with each Python call.

Events captured:
  - [:snakepit, :python, :call, :start]   - When a Python call begins
  - [:snakepit, :python, :call, :stop]    - When a Python call completes
  - [:snakepit, :python, :call, :exception] - When a Python call fails

SnakeBridge also enriches these events via RuntimeForwarder:
  - [:snakebridge, :runtime, :call, :start]
  - [:snakebridge, :runtime, :call, :stop]
  - [:snakebridge, :runtime, :call, :exception]

================================================================================


================================================================================
                SECTION 1: Basic Calls with Telemetry Events
================================================================================

Each Python call emits telemetry events that we capture and display inline.
Watch for the [:snakepit, :python, :call, :start] and :stop events!


┌─ Calculate square root of 144
│
│  Elixir call:     Math.sqrt/1
│  Python module:   math
│  Arguments:       [144]
│
│  Response from Python (252557 us)
│
└─ Result: {:ok, 12.0}

┌─ Calculate sin(1.0)
│
│  Elixir call:     Math.sin/1
│  Python module:   math
│  Arguments:       [1.0]
│
│  Response from Python (1442 us)
│
└─ Result: {:ok, 0.8414709848078965}

┌─ Calculate 2^10
│
│  Elixir call:     Math.pow/2
│  Python module:   math
│  Arguments:       [2, 10]
│
│  Response from Python (1065 us)
│
└─ Result: {:ok, 1024.0}

┌─ Calculate floor of 3.7
│
│  Elixir call:     Math.floor/1
│  Python module:   math
│  Arguments:       [3.7]
│
│  Response from Python (893 us)
│
└─ Result: {:ok, 3.0}


================================================================================
                SECTION 2: Error Events in Telemetry
================================================================================

When Python calls fail, telemetry captures the exception event.
This allows monitoring systems to track error rates and patterns.


┌─ Calculate sqrt(-1) - expected to fail!
│
│  Elixir call:     Math.sqrt/1
│  Python module:   math
│  Arguments:       [-1]
│
│  Error from Python (5246 us)
│
└─ Result: {:error, %Snakepit.Error.ValueError{message: "math domain error", context: %{"function" => "sqrt", "library" => "math", "python_module" => "math", "session_id" => "session_1_1766875608065029", "tool_name" => "snakebridge.call"}, stacktrace: ["Traceback (most recent call last):\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py\", line 470, in ExecuteTool\n    result_data = adapter.execute_tool(\n                  ^^^^^^^^^^^^^^^^^^^^^\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 584, in execute_tool\n    return func(*args, **kwargs)\n           ^^^^^^^^^^^^^^^^^^^^^\n", "ValueError: math domain error\n"], python_type: "ValueError", python_traceback: "Traceback (most recent call last):\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py\", line 470, in ExecuteTool\n    result_data = adapter.execute_tool(\n                  ^^^^^^^^^^^^^^^^^^^^^\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 584, in execute_tool\n    return func(*args, **kwargs)\n           ^^^^^^^^^^^^^^^^^^^^^\nValueError: math domain error\n"}}

┌─ Call non-existent module - expected to fail!
│
│  Elixir call:     NonExistent.foo/0
│  Python module:   this_module_does_not_exist
│  Arguments:       (none)
│
│  Error from Python (4817 us)
│
└─ Result: {:error, %Snakepit.Error.PythonException{message: "No module named 'this_module_does_not_exist'", context: %{"function" => "foo", "library" => "this_module_does_not_exist", "python_module" => "this_module_does_not_exist", "session_id" => "session_1_1766875608065029", "tool_name" => "snakebridge.call"}, stacktrace: ["Traceback (most recent call last):\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py\", line 470, in ExecuteTool\n    result_data = adapter.execute_tool(\n                  ^^^^^^^^^^^^^^^^^^^^^\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 582, in execute_tool\n    mod = _import_module(python_module)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n", "  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 293, in _import_module\n    mod = importlib.import_module(module_name)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n", "  File \"/usr/lib/python3.12/importlib/__init__.py\", line 90, in import_module\n    return _bootstrap._gcd_import(name[level:], package, level)\n           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n", "  File \"<frozen importlib._bootstrap>\", line 1387, in _gcd_import\n", "  File \"<frozen importlib._bootstrap>\", line 1360, in _find_and_load\n", "  File \"<frozen importlib._bootstrap>\", line 1324, in _find_and_load_unlocked\n", "ModuleNotFoundError: No module named 'this_module_does_not_exist'\n"], python_type: "ModuleNotFoundError", python_traceback: "Traceback (most recent call last):\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakepit/priv/python/grpc_server.py\", line 470, in ExecuteTool\n    result_data = adapter.execute_tool(\n                  ^^^^^^^^^^^^^^^^^^^^^\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 582, in execute_tool\n    mod = _import_module(python_module)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n  File \"/home/home/p/g/n/snakebridge/examples/telemetry_showcase/_build/dev/lib/snakebridge/priv/python/snakebridge_adapter.py\", line 293, in _import_module\n    mod = importlib.import_module(module_name)\n          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n  File \"/usr/lib/python3.12/importlib/__init__.py\", line 90, in import_module\n    return _bootstrap._gcd_import(name[level:], package, level)\n           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n  File \"<frozen importlib._bootstrap>\", line 1387, in _gcd_import\n  File \"<frozen importlib._bootstrap>\", line 1360, in _find_and_load\n  File \"<frozen importlib._bootstrap>\", line 1324, in _find_and_load_unlocked\nModuleNotFoundError: No module named 'this_module_does_not_exist'\n"}}


================================================================================
                SECTION 3: Concurrent Calls with Interleaved Events
================================================================================

When multiple calls happen concurrently, telemetry events may interleave.
This demonstrates how telemetry captures the true execution order.

Starting 5 concurrent Python calls...


│
│  Waiting for all concurrent calls to complete...
│
│  [Concurrent] sqrt(100) = 10.0 (1342 us)
│  [Concurrent] cos(0) = 1.0 (2418 us)
│  [Concurrent] sin(0) = 0.0 (3064 us)
│  [Concurrent] floor(3.7) = 3.0 (3391 us)
│  [Concurrent] ceil(2.3) = 3.0 (4021 us)
│
│  All 5 concurrent calls completed!
│
└─ Concurrent execution finished


================================================================================
                          TELEMETRY METRICS SUMMARY
================================================================================

  Total calls:        0
  Successful calls:   0
  Failed calls:       0
  Error rate:         0.0%

  Total duration:     0 us
  Average duration:   0.0 us
  Min duration:       0 us
  Max duration:       0 us

  Events captured:    0

================================================================================


================================================================================
                          DEMO COMPLETE
================================================================================

What you learned:
  1. Telemetry events are emitted automatically for every Python call
  2. Events include timing measurements (duration in native units)
  3. Error events capture exception details for monitoring
  4. Concurrent calls produce interleaved events
  5. Aggregate metrics help track overall system health

To integrate telemetry in your own app:
  1. Use :telemetry.attach/4 to subscribe to events
  2. Forward metrics to your observability stack (Prometheus, Datadog, etc.)
  3. Use telemetry_metrics for aggregation

================================================================================


12:46:48.441 [notice] Application snakepit exited: :stopped

✓ telemetry_showcase completed in 3s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 7/8: proof_pipeline
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Python 3.12.3 is already installed
Running demo...

Python 3.12.3 is already installed

12:46:50.340 [info] Loading 146 CA(s) from :otp store

12:46:50.347 [info] OTLP exporter successfully initialized

12:46:50.837 [notice] Application snakepit exited: :stopped
╔═══════════════════════════════════════════════════════════╗
║            ProofPipeline - SnakeBridge Demo               ║
╚═══════════════════════════════════════════════════════════╝

Input:
  prompt_latex:  "\\frac{d}{dx} x^2"
  student_latex: "2x"
  gold_latex:    "2 x"

Running live pipeline (requires Python libs installed)...

────────────────────────────────────────────────────────────

┌─ 1. PyLatexEnc.Latexwalker.LatexWalker.new/1
│  Python module:   pylatexenc.latexwalker
│  Python function: LatexWalker
│  Arguments:       ["2x"]
│
└─ Result: {:ok,
     %{"__snakebridge_ref__" => true, "library" => "pylatexenc", "python_module" => "pylatexenc.latexwalker", "ref_id" => "0a8e22f3086e472ea30b9d2a0d0ac8d9", "session_id" => "session_7_1766875611269832"}}

┌─ 2. PyLatexEnc.Latexwalker.LatexWalker.get_latex_nodes/1
│  Python module:   pylatexenc.latexwalker
│  Python function: get_latex_nodes
│  Arguments:       ["<walker_ref>"]
│
└─ Result: {:ok,
     "([LatexCharsNode(parsing_state=<parsing state 128451542454000>, pos=0, len=2, chars='2x')], 0, 2)"}

┌─ 3. ProofPipeline.PythonParser.parse_expr/1
│  Python module:   sympy.parsing.latex
│  Python function: parse_latex
│  Arguments:       ["2x"]
│
└─ Result: {:ok, "2*x"}

┌─ 4. Sympy.simplify/1
│  Python module:   sympy
│  Python function: simplify
│  Arguments:       ["2*x"]
│
└─ Result: {:ok, "2*x"}

┌─ 5. Sympy.latex/1
│  Python module:   sympy
│  Python function: latex
│  Arguments:       ["2*x"]
│
└─ Result: {:ok, "\\mathtt{\\text{2*x}}"}

┌─ 6. MathVerify.verify/2
│  Python module:   math_verify
│  Python function: verify
│  Arguments:       ["2 x", "\\mathtt{\\text{2*x}}"]
│
└─ Result: {:ok, 0.0}

┌─ 7. MathVerify.parse/1
│  Python module:   math_verify
│  Python function: parse
│  Arguments:       ["\\mathtt{\\text{2*x}}"]
│
└─ Result: {:ok, []}

════════════════════════════════════════════════════════════
PIPELINE COMPLETE
════════════════════════════════════════════════════════════

Final Result:
%{
  input: %{
    prompt_latex: "\\frac{d}{dx} x^2",
    student_latex: "2x",
    gold_latex: "2 x"
  },
  nodes: "([LatexCharsNode(parsing_state=<parsing state 128451542454000>, pos=0, len=2, chars='2x')], 0, 2)",
  rendered: "\\mathtt{\\text{2*x}}",
  simplified: "2*x",
  verdict: 0.0,
  parsed: [],
  normalized: "\\mathtt{\\text{2*x}}"
}

12:46:52.077 [notice] Application snakepit exited: :stopped

✓ proof_pipeline completed in 4s

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Example 8/8: twenty_libraries
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Compiling...
Running demo...


12:46:53.401 [info] Loading 146 CA(s) from :otp store

12:46:53.408 [info] OTLP exporter successfully initialized

12:46:53.921 [notice] Application snakepit exited: :stopped

╔════════════════════════════════════════════════════════════╗
║  SnakeBridge: 20 Python Libraries Over gRPC               ║
╚════════════════════════════════════════════════════════════╝

Library 1/20: math
┌─ factorial(...)
│  Arguments: ~c"\n"
└─ Result: {:ok, 3628800.0}  (269.7260 ms)

┌─ sqrt(...)
│  Arguments: [144]
└─ Result: {:ok, 12.0}  (1.6410 ms)

Library 2/20: json
┌─ dumps(...)
│  Arguments: [%{"count" => 42, "hello" => "world"}]
└─ Result: {:ok, "{\"count\": 42, \"hello\": \"world\"}"}  (1.2460 ms)

┌─ loads(...)
│  Arguments: ["{\"parsed\": true, \"value\": 123}"]
└─ Result: {:ok, %{"parsed" => true, "value" => 123}}  (1.2640 ms)

Library 3/20: os
┌─ getcwd(...)
│  Arguments: []
└─ Result: {:ok, "/home/home/p/g/n/snakebridge/examples/twenty_libraries/d...}  (1.0850 ms)

┌─ getenv(...)
│  Arguments: ["PATH"]
└─ Result: {:ok, "/home/home/.asdf/installs/erlang/28.1.1/erts-16.1.1/bin:...}  (899.0000 us)

Library 4/20: sys
┌─ getrecursionlimit(...)
│  Arguments: []
└─ Result: {:ok, 1000.0}  (872.0000 us)

┌─ getsizeof(...)
│  Arguments: ~c"d"
└─ Result: {:ok, 28.0}  (802.0000 us)

Library 5/20: platform
┌─ system(...)
│  Arguments: []
└─ Result: {:ok, "Linux"}  (844.0000 us)

┌─ python_version(...)
│  Arguments: []
└─ Result: {:ok, "3.12.3"}  (1.0350 ms)

Library 6/20: datetime
┌─ datetime(...)
│  Arguments: [2024, 12, 25, ...]
└─ Result: {:ok, "2024-12-25 10:30:00"}  (1.0350 ms)

┌─ date(...)
│  Arguments: [2024, 1, 1]
└─ Result: {:ok, "2024-01-01"}  (955.0000 us)

Library 7/20: random
┌─ random(...)
│  Arguments: []
└─ Result: {:ok, 0.04284151727608709}  (879.0000 us)

┌─ randint(...)
│  Arguments: [1, 100]
└─ Result: {:ok, 76.0}  (899.0000 us)

Library 8/20: copy
┌─ copy(...)
│  Arguments: [[1, 2, ...]]
└─ Result: {:ok, [1, 2, 3]}  (851.0000 us)

┌─ deepcopy(...)
│  Arguments: [%{"nested" => [1, ...]}]
└─ Result: {:ok, %{"nested" => [1, 2, 3]}}  (818.0000 us)

Library 9/20: base64
┌─ b64decode(...)
│  Arguments: ["SGVsbG8sIFNuYWtlQnJpZGdlIQ=="]
└─ Result: {:ok, "b'Hello, SnakeBridge!'"}  (784.0000 us)

┌─ b64decode(...)
│  Arguments: ["SGVsbG8gV29ybGQh"]
└─ Result: {:ok, "b'Hello World!'"}  (803.0000 us)

Library 10/20: urllib_parse
┌─ quote(...)
│  Arguments: ["hello world/test"]
└─ Result: {:ok, "hello%20world/test"}  (830.0000 us)

┌─ unquote(...)
│  Arguments: ["hello%20world%2Ftest"]
└─ Result: {:ok, "hello world/test"}  (920.0000 us)

Library 11/20: re
┌─ match(...)
│  Arguments: ["\\d+", "123abc"]
└─ Result: {:ok, "<re.Match object; span=(0, 3), match='123'>"}  (883.0000 us)

┌─ search(...)
│  Arguments: ["[a-z]+", "123abc456"]
└─ Result: {:ok, "<re.Match object; span=(3, 6), match='abc'>"}  (935.0000 us)

Library 12/20: collections
┌─ Counter(...)
│  Arguments: [["a", "b", ...]]
└─ Result: {:ok, %{"a" => 3, "b" => 2, "c" => 1}}  (906.0000 us)

┌─ Counter(...)
│  Arguments: [["red", "blue", ...]]
└─ Result: {:ok, %{"blue" => 3, "green" => 1, "red" => 2}}  (826.0000 us)

Library 13/20: itertools
┌─ combinations(...)
│  Arguments: [["a", "b", ...], 2]
└─ Result: {:ok, "<itertools.combinations object at 0x76cfc6ea7fb0>"}  (944.0000 us)

┌─ permutations(...)
│  Arguments: [["x", "y"], 2]
└─ Result: {:ok, "<itertools.permutations object at 0x76cfc6ea7a60>"}  (764.0000 us)

Library 14/20: operator
┌─ add(...)
│  Arguments: [10, 20]
└─ Result: {:ok, 30.0}  (782.0000 us)

┌─ mul(...)
│  Arguments: [5, 7]
└─ Result: {:ok, 35.0}  (1.0900 ms)

Library 15/20: string
┌─ capwords(...)
│  Arguments: ["hello world from elixir"]
└─ Result: {:ok, "Hello World From Elixir"}  (888.0000 us)

┌─ capwords(...)
│  Arguments: ["snakebridge is awesome"]
└─ Result: {:ok, "Snakebridge Is Awesome"}  (1.0960 ms)

Library 16/20: textwrap
┌─ wrap(...)
│  Arguments: ["The quick brown fox jumps over the lazy dog", 20]
└─ Result: {:ok, ["The quick brown fox", "jumps over the lazy", "dog"]}  (920.0000 us)

┌─ fill(...)
│  Arguments: ["SnakeBridge enables seamless Python interop", 25]
└─ Result: {:ok, "SnakeBridge enables\nseamless Python interop"}  (852.0000 us)

Library 17/20: uuid
┌─ uuid4(...)
│  Arguments: []
└─ Result: {:ok, "d6e1354f-502d-4893-ad2c-eeb07a703b2b"}  (932.0000 us)

┌─ uuid4(...)
│  Arguments: []
└─ Result: {:ok, "bf286269-93ca-4b1e-a78d-4aaa67ac9439"}  (919.0000 us)

Library 18/20: time
┌─ time(...)
│  Arguments: []
└─ Result: {:ok, 1766875614.7074738}  (887.0000 us)

┌─ ctime(...)
│  Arguments: []
└─ Result: {:ok, "Sat Dec 27 12:46:54 2025"}  (793.0000 us)

Library 19/20: calendar
┌─ isleap(...)
│  Arguments: [2024]
└─ Result: {:ok, 1.0}  (874.0000 us)

┌─ monthrange(...)
│  Arguments: [2024, 2]
└─ Result: {:ok, "(calendar.THURSDAY, 29)"}  (854.0000 us)

Library 20/20: statistics
┌─ mean(...)
│  Arguments: [[10, 20, ...]]
└─ Result: {:ok, 30.0}  (4.4980 ms)

┌─ stdev(...)
│  Arguments: [[10, 20, ...]]
└─ Result: {:ok, 15.811388300841896}  (1.0590 ms)

════════════════════════════════════════════════════════════
SUMMARY
────────────────────────────────────────────────────────────
Total libraries called:  20
Total calls made:        40  (2 per library)
Successful calls:        40
Failed calls:            0
Total time:              309.8900 ms
Average per call:        7.7473 ms
Fastest:                 itertools.permutations (764.0000 us)
Slowest:                 math.factorial (269.7260 ms)
════════════════════════════════════════════════════════════


12:46:54.801 [notice] Application snakepit exited: :stopped

✓ twenty_libraries completed in 2s

═══════════════════════════════════════════════════════════════════════════
                           SUMMARY
═══════════════════════════════════════════════════════════════════════════

Started:   2025-12-27 12:46:30
Finished:  2025-12-27 12:46:54
Duration:  0m 24s (24 seconds)

Examples Run:
  ✓ basic (3s)
  ✓ math_demo (4s)
  ✓ types_showcase (3s)
  ✓ error_showcase (2s)
  ✓ docs_showcase (3s)
  ✓ telemetry_showcase (3s)
  ✓ proof_pipeline (4s)
  ✓ twenty_libraries (2s)

All 8 examples passed!

═══════════════════════════════════════════════════════════════════════════

   _____                      _      _       _
  / ____|                    | |    | |     | |
 | |     ___  _ __ ___  _ __ | | ___| |_ ___| |
 | |    / _ \| '_ ` _ \| '_ \| |/ _ \ __/ _ \ |
 | |___| (_) | | | | | | |_) | |  __/ ||  __/_|
  \_____\___/|_| |_| |_| .__/|_|\___|\__\___(_)
                       | |
                       |_|
````
