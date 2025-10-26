# SnakeBridge Test Suite

**Comprehensive test coverage** for the SnakeBridge Python integration framework.

---

## Test Structure

```
test/
├── test_helper.exs                      # Test setup, mocks, ExUnit config
├── support/
│   ├── test_fixtures.ex                 # Shared fixtures and sample data
│   └── test_behaviours.ex               # Mock behaviours for protocols
├── unit/                                # Unit tests (fast, isolated)
│   ├── config_test.exs                  # Config schema validation
│   ├── generator_test.exs               # Code generation
│   ├── discovery/
│   │   └── introspector_test.exs        # Introspection logic
│   ├── schema/
│   │   └── differ_test.exs              # Schema diffing
│   └── type_system/
│       └── mapper_test.exs              # Type mapping Python ↔ Elixir
├── integration/                         # Integration tests (slower, cross-component)
│   └── end_to_end_test.exs              # Full workflow tests
└── property/                            # Property-based tests (generative)
    ├── config_properties_test.exs       # Config invariants
    └── type_mapper_properties_test.exs  # Type system properties
```

---

## Test Categories

### 1. Unit Tests (`test/unit/`)

**Fast, isolated tests** for individual components.

**Coverage**:
- ✅ **Config**: Validation, composition, serialization, caching
- ✅ **TypeSystem.Mapper**: Python ↔ Elixir type conversion
- ✅ **Discovery.Introspector**: Schema discovery and parsing
- ✅ **Schema.Differ**: Git-style diffing between schemas
- ✅ **Generator**: AST generation, optimization passes

**Run**: `mix test test/unit`

**Characteristics**:
- Async: Yes
- Mocking: Mox for protocols
- Avg runtime: <50ms per test

### 2. Integration Tests (`test/integration/`)

**Cross-component tests** verifying workflows.

**Coverage**:
- ✅ **End-to-end workflow**: Discover → Generate → Execute
- ✅ **Config caching**: Store → Load → Verify
- ✅ **Incremental regeneration**: Diff → Update modules
- ✅ **Error handling**: Graceful failures across layers

**Run**: `mix test --only integration`

**Characteristics**:
- Async: No (shares state)
- Mocking: Partial (mocked Snakepit)
- Avg runtime: 100-500ms per test
- Tagged: `:integration`, `:slow`

### 3. Property-Based Tests (`test/property/`)

**Generative tests** verifying invariants.

**Coverage**:
- ✅ **Config hashing**: Consistency, uniqueness
- ✅ **Serialization**: Roundtrip preservation
- ✅ **Type inference**: Coverage of all Elixir types
- ✅ **Type conversion**: Valid AST generation

**Run**: `mix test test/property`

**Characteristics**:
- Async: Yes
- Framework: StreamData
- Runs: 100 iterations per property (configurable)
- Shrinking: Automatic on failure

---

## Running Tests

### All Tests
```bash
cd snakebridge
mix test
```

### By Category
```bash
# Unit tests only (fastest)
mix test test/unit

# Integration tests
mix test --only integration

# Property-based tests
mix test test/property

# Exclude slow tests
mix test --exclude slow

# Exclude external dependencies
mix test --exclude external
```

### With Coverage
```bash
mix coveralls
mix coveralls.html  # Generate HTML report
```

### Watch Mode
```bash
mix test.watch
mix test.watch --stale  # Only changed files
```

### Quality Check
```bash
mix quality           # Format + Credo + Dialyzer
mix quality.ci        # CI version (strict)
```

---

## Test Helpers

### Fixtures (`test/support/test_fixtures.ex`)

Provides sample data for tests:

```elixir
# Sample Python class descriptor
TestFixtures.sample_class_descriptor()

# Sample SnakeBridge config
TestFixtures.sample_config()

# Sample introspection response
TestFixtures.sample_introspection_response()

# Sample type descriptors
TestFixtures.sample_type_descriptors()
```

### Mocks

**Mox (compile-time)**:
- `SnakeBridge.Discovery.IntrospectorMock`
- `SnakeBridge.Runtime.ExecutorMock`
- `SnakeBridge.Schema.ValidatorMock`

**Mimic (runtime)**:
- `SnakeBridge.Discovery.Introspector`
- `SnakeBridge.Runtime.Executor`

---

## Test Patterns

### Unit Test Pattern
```elixir
defmodule SnakeBridge.MyComponentTest do
  use ExUnit.Case, async: true  # Async for speed

  import Mox  # For protocol mocks
  alias SnakeBridge.TestFixtures

  setup :verify_on_exit!  # Ensure mocks are called

  describe "feature" do
    test "behavior" do
      # Arrange
      input = TestFixtures.sample_data()

      # Act
      result = MyComponent.function(input)

      # Assert
      assert result == expected
    end
  end
end
```

### Property Test Pattern
```elixir
defmodule SnakeBridge.Property.MyComponentTest do
  use ExUnit.Case
  use ExUnitProperties  # Property-based testing

  property "invariant holds for all inputs" do
    check all(
      input <- generator(),
      max_runs: 100
    ) do
      result = MyComponent.function(input)

      assert invariant(result)
    end
  end
end
```

### Integration Test Pattern
```elixir
defmodule SnakeBridge.Integration.WorkflowTest do
  use ExUnit.Case  # No async

  @moduletag :integration  # Tag for filtering

  test "full workflow" do
    # Setup
    config = build_config()

    # Execute workflow
    {:ok, result} = Workflow.run(config)

    # Verify end state
    assert result.status == :success
  end
end
```

---

## Coverage Goals

| Component | Target | Current |
|-----------|--------|---------|
| **Config** | 95% | 🔲 TBD |
| **TypeSystem** | 90% | 🔲 TBD |
| **Discovery** | 85% | 🔲 TBD |
| **Generator** | 90% | 🔲 TBD |
| **Schema** | 90% | 🔲 TBD |
| **Runtime** | 80% | 🔲 TBD |
| **Overall** | **90%** | 🔲 TBD |

Run `mix coveralls.html` to generate coverage report.

---

## Continuous Integration

### GitHub Actions Workflow

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'

      - name: Install dependencies
        run: mix deps.get

      - name: Run tests
        run: mix test

      - name: Run quality checks
        run: mix quality.ci

      - name: Generate coverage
        run: mix coveralls.github
```

---

## Writing New Tests

### Checklist

When adding a new module, ensure:

- [ ] Unit tests for public functions
- [ ] Edge cases covered
- [ ] Error cases tested
- [ ] Mocks for external dependencies
- [ ] Documentation examples tested (doctest)
- [ ] Property tests for invariants (if applicable)
- [ ] Integration test for workflows (if applicable)

### Example: Adding Tests for New Module

```bash
# 1. Create test file
touch test/unit/my_new_module_test.exs

# 2. Add fixtures if needed
# Edit: test/support/test_fixtures.ex

# 3. Run tests
mix test test/unit/my_new_module_test.exs

# 4. Check coverage
mix coveralls.html
open cover/excoveralls.html
```

---

## Debugging Tests

### Verbose Output
```bash
mix test --trace          # Show test names
mix test --max-failures 1 # Stop on first failure
```

### Interactive Debugging
```elixir
test "with debugging" do
  require IEx
  IEx.pry  # Breakpoint

  result = MyModule.function()

  assert result
end
```

### Print Debugging
```elixir
test "with IO" do
  result = MyModule.function()
  IO.inspect(result, label: "RESULT")

  assert result
end
```

---

## Performance Testing

### Benchmarking (future)
```bash
mix bench  # Benchee integration (to be added)
```

### Memory Profiling
```elixir
:eprof.start()
:eprof.start_profiling([self()])
# ... run code ...
:eprof.stop_profiling()
:eprof.analyze()
```

---

## Test Maintenance

### Keep Tests Fast
- Mock external dependencies
- Use `async: true` when possible
- Avoid `Process.sleep/1`
- Tag slow tests with `:slow`

### Keep Tests Reliable
- Avoid timing dependencies
- Use deterministic data
- Clean up after yourself
- Avoid global state

### Keep Tests Readable
- Use descriptive test names
- One assertion per test (guideline)
- Use `describe` blocks for organization
- Add comments for non-obvious logic

---

## Resources

- [ExUnit Documentation](https://hexdocs.pm/ex_unit/ExUnit.html)
- [Mox Documentation](https://hexdocs.pm/mox/Mox.html)
- [StreamData Documentation](https://hexdocs.pm/stream_data/StreamData.html)
- [Mimic Documentation](https://hexdocs.pm/mimic/Mimic.html)

---

**Status**: Test suite scaffolded, ready for implementation
**Next**: Implement actual module code to make tests pass
