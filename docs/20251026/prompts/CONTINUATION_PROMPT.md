# SnakeBridge TDD Continuation Prompt

**Version**: 0.2.0
**Date**: 2025-10-26
**Status**: Live Python integration working, generator needs function support

---

## CONTEXT

### What SnakeBridge Is

A metaprogramming framework that automatically generates type-safe Elixir modules from Python library introspection. Eliminates thousands of lines of manual wrapper code.

**Value**: Integrate ANY Python library in seconds vs hours of manual code writing.

### Current Status

**Working**:
- ✅ 88 tests passing (76 Elixir + 12 Python, 100% pass rate)
- ✅ Complete Python adapter (`SnakeBridgeAdapter`) - introspects and executes any Python library
- ✅ Mix tasks (discover, validate, generate, clean)
- ✅ Public API (discover, generate, integrate)
- ✅ Live examples work (json, numpy)
- ✅ Real Python execution via Snakepit gRPC
- ✅ Published to Hex.pm (v0.2.0)

**Limitation**:
- ⚠️ Generator only creates modules for **classes**, not **functions**
- This blocks: `Numpy.mean([1,2,3])` - functions are discovered but not generated

---

## REQUIRED READING

### Core Implementation (Read These First)

1. **lib/snakebridge/generator.ex** (200 lines)
   - Current: `generate_module/2` only handles classes
   - Needed: Also handle module-level functions
   - Key function: `generate_all/1` at line 191

2. **lib/snakebridge/discovery.ex** (88 lines)
   - `schema_to_config/2` converts discovered schema to config
   - Currently: Only processes classes (line 44-58)
   - Needed: Also process functions properly

3. **lib/snakebridge/runtime.ex** (80 lines)
   - `create_instance/4` - for classes
   - `call_method/4` - for instance methods
   - Needed: `call_function/3` - for module-level functions

### Test Files (Understand Test Patterns)

4. **test/unit/generator_test.exs** (120 lines)
   - Shows how to test generator
   - Pattern: Generate AST → Macro.to_string → assert contains expected code

5. **test/unit/generated_module_runtime_test.exs** (131 lines)
   - Tests that generated modules call Runtime
   - Pattern: Generate → Compile → Execute → Verify result

6. **test/integration/end_to_end_test.exs** (93 lines)
   - Full workflow tests
   - Pattern: Discover → Generate → Execute

### Python Adapter (Understand What's Available)

7. **priv/python/snakebridge_adapter/adapter.py** (360 lines)
   - `describe_library` - returns `{"functions": {...}, "classes": {...}}`
   - `call_python` - handles both functions and class instances
   - Working and tested (12/12 Python tests passing)

### Documentation (Context for Design)

8. **docs/20251026/BASE_FUNCTIONALITY_ROADMAP.md**
   - Next steps: Prove base functionality works
   - Strategy: Build simple examples first

9. **STATUS.md**
   - Current implementation status
   - What's complete vs what's missing

10. **test/TESTING_STRATEGY.md**
    - Three-tier testing: Pure Elixir, Mocked Snakepit, Real Python
    - Adapter pattern for testing

### Examples (See What Users Need)

11. **examples/json_live.exs** (23 lines)
    - Currently fails: can't call json.dumps (function not generated)
    - Should work after fix

12. **examples/numpy_math.exs** (30 lines)
    - Discovers 626 NumPy functions
    - Can't call them yet (not generated)

---

## TASK

Add support for **module-level function generation** using TDD process.

### Success Criteria

1. **Tests pass**: All existing 88 tests + new function tests
2. **No warnings**: Clean compilation
3. **Examples work live**: `elixir examples/json_live.exs` successfully calls `json.dumps()`
4. **Functions callable**: `Numpy.mean([1,2,3])` works

---

## INSTRUCTIONS

### TDD Process (Follow Religiously)

#### Phase 1: Write Tests First (RED)

**File**: Create `test/unit/function_generation_test.exs`

```elixir
defmodule SnakeBridge.FunctionGenerationTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.{Generator, TestFixtures}

  describe "generate_function_module/2" do
    test "generates module for Python functions" do
      # Test fixture with functions, not classes
      descriptor = %{
        name: "JsonFunctions",
        python_path: "json",
        functions: [
          %{name: "dumps", elixir_name: :dumps},
          %{name: "loads", elixir_name: :loads}
        ]
      }

      config = TestFixtures.sample_config()
      ast = Generator.generate_function_module(descriptor, config)
      code = Macro.to_string(ast)

      # Verify module structure
      assert code =~ "defmodule"
      assert code =~ "def dumps("
      assert code =~ "def loads("
      assert code =~ "SnakeBridge.Runtime.call_function"
    end

    test "function modules call Runtime.call_function not create_instance" do
      # Functions are stateless, don't create instances
      # ...
    end
  end
end
```

**Run**: `mix test test/unit/function_generation_test.exs`
**Expected**: Tests FAIL (function not implemented)

#### Phase 2: Implement Minimal Code (GREEN)

**File**: Update `lib/snakebridge/generator.ex`

Add new function:
```elixir
@doc """
Generate module for Python module-level functions.

Different from class modules - no instance creation, direct function calls.
"""
def generate_function_module(descriptor, config) do
  # Similar to generate_module but for functions
  # Call Runtime.call_function instead of create_instance
end
```

Update `generate_all/1` to handle both classes AND functions:
```elixir
def generate_all(%SnakeBridge.Config{} = config) do
  case SnakeBridge.Config.validate(config) do
    {:ok, valid_config} ->
      # Generate class modules
      class_modules = generate_class_modules(valid_config.classes, valid_config)

      # Generate function modules (NEW!)
      function_modules = generate_function_modules(valid_config.functions, valid_config)

      all_modules = class_modules ++ function_modules
      {:ok, all_modules}
  end
end
```

**Run**: `mix test test/unit/function_generation_test.exs`
**Expected**: Tests PASS

#### Phase 3: Add Runtime Support

**File**: Update `lib/snakebridge/runtime.ex`

Add:
```elixir
@doc """
Call a module-level Python function (not a method on an instance).
"""
def call_function(python_path, function_name, args, opts \\ []) do
  session_id = Keyword.get(opts, :session_id, generate_session_id())
  adapter = snakepit_adapter()

  # Call without instance_id - direct function call
  case adapter.execute_in_session(session_id, "call_python", %{
    "module_path" => python_path,
    "function_name" => function_name,
    "args" => [],
    "kwargs" => args
  }) do
    {:ok, %{"success" => true, "result" => result}} -> {:ok, result}
    {:ok, %{"success" => false, "error" => error}} -> {:error, error}
    {:error, reason} -> {:error, reason}
  end
end
```

#### Phase 4: Update Discovery

**File**: `lib/snakebridge/discovery.ex`

Fix `schema_to_config/2` to better handle functions:
```elixir
defp convert_functions(functions_map) do
  # Currently creates basic function configs
  # Need to ensure they're in format generator expects
end
```

#### Phase 5: Integration Tests

**File**: Create `test/integration/function_execution_test.exs`

```elixir
@moduletag :integration
@moduletag :real_python

test "can call json.dumps from generated module" do
  {:ok, schema} = SnakeBridge.discover("json")
  config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "json")
  {:ok, modules} = SnakeBridge.generate(config)

  # Find the module with dumps function
  json_module = Enum.find(modules, fn m ->
    function_exported?(m, :dumps, 1)
  end)

  # Call it
  {:ok, result} = json_module.dumps(%{obj: %{test: "data"}})

  assert is_binary(result)
  assert result =~ "test"
end
```

#### Phase 6: Update Examples

Once tests pass, update `examples/json_live.exs`:

```elixir
# Should now work:
{:ok, json_string} = Json.dumps(%{obj: %{hello: "world"}})
{:ok, decoded} = Json.loads(%{s: json_string})
```

#### Phase 7: Verify All Tests Still Pass

```bash
mix test  # All 88+ tests should pass
```

---

## CONSTRAINTS

### MUST Follow TDD

1. **Write test first** (RED)
2. **Implement minimal code** (GREEN)
3. **Run test** - verify it passes
4. **Run full suite** - verify nothing broke
5. **Refactor if needed**
6. **Repeat**

### MUST Maintain

- ✅ All existing 88 tests passing
- ✅ Zero compiler warnings
- ✅ Examples work live (not mocks)
- ✅ Clean git history with good commit messages

### Code Style

- Follow existing patterns in generator.ex
- Use `Map.get/3` for descriptor access (atom and string keys)
- Add proper @doc and @spec
- Handle errors gracefully
- Keep functions small and focused

---

## EXPECTED CHANGES

### Files to Create
- `test/unit/function_generation_test.exs` (~80 lines)
- `test/integration/function_execution_test.exs` (~60 lines)

### Files to Modify
- `lib/snakebridge/generator.ex` (~100 lines added)
- `lib/snakebridge/runtime.ex` (~30 lines added)
- `lib/snakebridge/discovery.ex` (~20 lines modified)
- `test/support/snakepit_mock.ex` (~20 lines for function calls)
- `examples/json_live.exs` (~20 lines added for actual calls)

### Estimated Effort
- Tests: 1-2 hours
- Implementation: 2-3 hours
- Verification: 30 min
- **Total: 4-6 hours**

---

## SUCCESS CRITERIA

### Must Achieve

1. **Run**: `mix test` → 95+ tests passing (88 existing + ~7 new)
2. **Run**: `elixir examples/json_live.exs` → Successfully calls json.dumps AND json.loads
3. **Run**: `elixir examples/numpy_math.exs` → Shows NumPy functions available
4. **No warnings** during compilation
5. **Clean git** with atomic commits

### Demo Should Show

```bash
$ elixir examples/json_live.exs

✓ Discovered json module
  Functions: ["dumps", "loads", "dump", "load", "detect_encoding"]

✓ Generated module: Json

🚀 Calling json.dumps...
  Input: %{message: "Hello", value: 42}
  Output: "{\"message\": \"Hello\", \"value\": 42}"

🚀 Calling json.loads...
  Input: "{\"test\": \"data\"}"
  Output: %{"test" => "data"}

✅ Roundtrip successful!
```

---

## ARCHITECTURE NOTES

### Current Generator Flow

```
Config.classes -> generate_module (for each class) -> Compile
```

### Needed Generator Flow

```
Config.classes -> generate_class_module (for each) -> Compile
Config.functions -> generate_function_module (group by module) -> Compile
```

### Function Module Structure

For module-level functions (like json.dumps), generate:

```elixir
defmodule Json do
  @moduledoc "Elixir wrapper for json module functions"

  @doc "Serialize obj to JSON string"
  @spec dumps(map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def dumps(args, opts \\ []) do
    SnakeBridge.Runtime.call_function(
      "json",
      "dumps",
      args,
      opts
    )
  end

  @doc "Deserialize JSON string to map"
  @spec loads(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def loads(args, opts \\ []) do
    SnakeBridge.Runtime.call_function(
      "json",
      "loads",
      args,
      opts
    )
  end
end
```

**Key differences from class modules**:
- No `@type t` (no instance tuple)
- No `create/2` function
- Functions take args directly, not instance_ref
- Call `Runtime.call_function` not `Runtime.call_method`

---

## DEBUGGING TIPS

### If Tests Fail

1. **Check generator AST**: `Macro.to_string(ast) |> IO.puts`
2. **Check what Python returns**: Run Python adapter tests
3. **Check mock responses**: Verify SnakepitMock returns expected format
4. **Run one test**: `mix test path/to/test.exs:line_number`

### If Examples Fail

1. **Check discovery worked**: Schema should have "functions" key
2. **Check config conversion**: Inspect config.functions list
3. **Check module generated**: `function_exported?(module, :dumps, 1)`
4. **Check Runtime call**: Add debug logging to see what's sent to Python

---

## COMMIT STRATEGY

Make atomic commits for each phase:

1. `"Add tests for function module generation (RED)"`
2. `"Implement generate_function_module (GREEN)"`
3. `"Add Runtime.call_function support"`
4. `"Update Discovery to handle functions properly"`
5. `"Update examples to call functions - all working live"`
6. `"All tests passing, function generation complete"`

Each commit should:
- Have meaningful message
- Leave tests in passing state (or clearly mark as WIP)
- Be reviewable independently

---

## CURRENT CODEBASE STRUCTURE

```
lib/snakebridge/
├── snakebridge.ex              # Public API
├── config.ex                   # Configuration schema
├── generator.ex                # ⚠️ NEEDS: Function support
├── runtime.ex                  # ⚠️ NEEDS: call_function/3
├── discovery.ex                # ⚠️ NEEDS: Better function handling
├── discovery/
│   ├── introspector.ex         # ✅ Complete
│   └── introspector_behaviour.ex
├── cache.ex                    # ✅ Complete
├── type_system/
│   └── mapper.ex               # ✅ Complete
└── schema/
    └── differ.ex               # ✅ Complete

priv/python/
└── snakebridge_adapter/
    └── adapter.py              # ✅ Complete (360 lines)
        - describe_library ✅
        - call_python ✅

test/
├── unit/
│   ├── generator_test.exs      # ✅ 9/9 passing
│   ├── generated_module_runtime_test.exs  # ✅ 6/6 passing
│   └── function_generation_test.exs       # 🔲 CREATE THIS
├── integration/
│   ├── end_to_end_test.exs     # ✅ 6/6 passing
│   └── function_execution_test.exs        # 🔲 CREATE THIS
└── support/
    └── snakepit_mock.ex        # ⚠️ UPDATE: Add function call support

examples/
├── api_demo.exs                # ✅ Works
├── json_live.exs               # ⚠️ Partial (discovers, can't call)
└── numpy_math.exs              # ⚠️ Partial (discovers, can't call)
```

---

## TEST DATA FIXTURES

Update `test/support/test_fixtures.ex` with:

```elixir
def sample_function_module_descriptor do
  %{
    name: "JsonFunctions",
    python_path: "json",
    docstring: "Python's built-in JSON encoder/decoder",
    functions: [
      %{
        name: "dumps",
        python_path: "json.dumps",
        elixir_name: :dumps,
        docstring: "Serialize object to JSON",
        parameters: [
          %{name: "obj", required: true, type: %{kind: "primitive", primitive_type: "any"}}
        ]
      },
      %{
        name: "loads",
        python_path: "json.loads",
        elixir_name: :loads,
        docstring: "Deserialize JSON to object",
        parameters: [
          %{name: "s", required: true, type: %{kind: "primitive", primitive_type: "str"}}
        ]
      }
    ]
  }
end
```

---

## MOCKPIT UPDATE

Update `test/support/snakepit_mock.ex` to handle function calls:

```elixir
defp call_python_response(%{"function_name" => func, "module_path" => "json"})
     when func in ["dumps", "loads"] do
  # Return appropriate mock data for json functions
  {:ok, %{
    "success" => true,
    "result" => if func == "dumps", do: "{\"mock\": true}", else: %{"mock" => true}
  }}
end
```

---

## VALIDATION CHECKLIST

Before considering complete:

- [ ] `mix test` - All tests pass (95+ tests)
- [ ] `mix test --warnings-as-errors` - No warnings
- [ ] `elixir examples/json_live.exs` - Completes successfully with real Python calls
- [ ] `elixir examples/numpy_math.exs` - Shows functions available
- [ ] `mix format --check-formatted` - Code formatted
- [ ] `git log --oneline -10` - Clean commit history
- [ ] Examples demonstrate function calling end-to-end

---

## HINTS

### Where to Start

1. Look at `generate_module/2` in generator.ex (line 16-59)
2. Copy the pattern but remove instance creation
3. Change `create/2` → direct function calls
4. Update `generate_all/1` to call both generators

### Common Pitfalls

- ❌ Don't break existing class generation
- ❌ Don't forget to handle both atom and string keys in descriptors
- ❌ Don't skip the mock updates (tests will fail)
- ✅ Test incrementally - one function at a time
- ✅ Keep commits atomic
- ✅ Run full test suite after each change

### Quick Win

Start with json module - only 5 functions, simple types, built-in (no install).

Once json works, numpy will work automatically (same pattern).

---

## DELIVERABLES

After completion:

1. **Tests**: 95+ passing, 0 failures
2. **Examples**: All 3 examples fully functional with live Python
3. **Documentation**: Update STATUS.md with "Function generation: ✅ Complete"
4. **Git**: Clean history with 5-7 atomic commits
5. **Verification**: Can call `Json.dumps()` and `Numpy.mean()` from Elixir

---

## FINAL NOTES

**This is the last major feature for v0.2.0.**

Once function generation works:
- SnakeBridge is feature-complete for basic use
- Can integrate ANY Python library (functions + classes)
- Examples prove it works end-to-end
- Ready for real-world usage

**Take your time. Follow TDD. Make it work correctly.**

The foundation is solid (88 tests passing). Just need this final piece.

---

**Ready to continue? Start with Phase 1: Write the tests.**
