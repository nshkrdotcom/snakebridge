# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- [ ] Configuration composition (extends, mixins)
- [ ] LSP server for config authoring
- [ ] Auto-generated test suites from schemas

## [0.2.3] - 2025-10-29

### Added
- Real Python integration status & roadmap (`docs/20251027/REAL_PYTHON_INTEGRATION_STATUS_AND_ROADMAP.md`) outlining milestones and blockers
- Comprehensive Python environment setup guide (`docs/PYTHON_SETUP.md`) and `.env.example` bootstrap for local runs
- Real Python integration test harness with documentation (`test/integration/README.md`, `test/integration/real_python_test.exs`)
- Deep dive research notes for Claude and Gemini tooling (`docs/20251027/*.md`) to inform future adapters

### Changed
- Quickstart instructions refreshed with real Python workflow updates (`examples/QUICKSTART.md`)
- Upgraded bundled Snakepit dependency to v0.6.7 to match new integration pipeline
- README highlights refined streaming tooling section and dependency guidance

### Fixed
- Eliminated Elixir test module redefinition warnings caused by upgraded Snakepit fixtures

## [0.2.2] - 2025-10-26

### Added - Streaming Everything Everywhere 🐍⚡
- ✅ **End-to-end streaming pipeline** powered by Snakepit v0.6.4 — `SnakeBridge.Runtime.execute_stream/5` now forwards streaming tools with chunk callbacks
- ✅ **GenAI adapter + example** showing real streaming feeds (`examples/genai_streaming.exs`, `examples/test_streaming_simple.exs`)
- ✅ **Python bridge enhancements** — new gRPC adapter wiring enables `execute_streaming_tool/4`

### Changed
- Live demos now share a unified helper that installs deps, configures Snakepit, and locates the correct Python interpreter automatically
- Updated examples (`live_demo`, `numpy_live`) to run against the published Snakepit package instead of local checkouts
- README refreshed with new streaming docs, commands, and dependency versions

### Fixed
- Ensured Mix examples no longer consume stale cached copies of Snakepit by configuring the path after `Mix.install/1`
- Python setup script now prefers a project-local virtualenv before falling back to the Snakepit repo venv

## [0.2.1] - 2025-10-26

### Added - Function Generation Support 🎉

**Core Implementation:**
- ✅ **`generate_function_module/2`** - Generates Elixir modules for Python module-level functions
- ✅ **`Runtime.call_function/4`** - Executes stateless Python functions (no instance required)
- ✅ **Function discovery** - Properly handles function descriptors from introspection
- ✅ **Mixed generation** - Can generate both classes AND functions from same config

**What This Enables:**
```elixir
# Call Python functions directly - no instance creation needed!
{:ok, schema} = SnakeBridge.discover("json")
config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "json")
{:ok, [json_module]} = SnakeBridge.generate(config)

{:ok, json_string} = json_module.dumps(%{obj: %{hello: "world"}})
{:ok, data} = json_module.loads(%{s: json_string})
```

**Examples Updated:**
- `examples/json_live.exs` - Now demonstrates full roundtrip: dumps() → loads()
- `examples/numpy_math.exs` - Shows NumPy function discovery (626 functions!)

**Key Differences from Class Modules:**
- No `@type t` (functions are stateless)
- No `create/2` function (direct function calls)
- Functions take args directly, not instance_ref
- Call `Runtime.call_function` instead of `Runtime.call_method`

### Added - Tests
- 8 new unit tests for function generation (`test/unit/function_generation_test.exs`)
- 7 new integration tests (`test/integration/function_execution_test.exs`)
- All tests following TDD methodology (RED → GREEN → REFACTOR)

### Changed
- `Discovery.convert_functions/1` now includes `name` field in function descriptors
- `SnakepitMock` updated with specific responses for json.dumps/loads
- `generate_all/1` now generates both class and function modules

### Fixed
- Function descriptors missing required `name` field
- SnakepitMock had duplicate `call_python_response` clause (compiler warning)

### Test Results
- **91 total tests** (up from 88)
- 8 properties + 83 unit/integration tests
- **100% pass rate** ✅
- Zero compilation warnings ✅

### Documentation
- README updated with function generation examples
- Configuration examples show both classes and functions
- DSPy example updated to demonstrate function calls

### Git History
Six atomic commits following TDD:
1. Add tests for function module generation (TDD RED phase)
2. Implement generate_function_module/2 and function generation (TDD GREEN phase)
3. Add Runtime.call_function/4 for module-level function calls
4. Update Discovery and SnakepitMock to properly handle functions
5. Add comprehensive integration tests for function execution
6. Update examples to demonstrate live function calling

## [0.2.0] - 2025-10-26

### Added - Live Python Integration
- **Complete Python adapter** (`SnakeBridgeAdapter`) for dynamic library integration
  - `describe_library` tool - introspects any Python module via inspect
  - `call_python` tool - executes functions, creates instances, calls methods
  - Generic adapter works with ANY Python library (json, numpy, requests, etc.)
  - 12 Python tests, all passing

### Added - User-Facing Tools
- **Public API**: `SnakeBridge.discover/2`, `generate/1`, `integrate/2`
- **Mix tasks**:
  - `mix snakebridge.discover` - discover Python libraries
  - `mix snakebridge.validate` - validate configs
  - `mix snakebridge.generate` - generate modules
  - `mix snakebridge.clean` - clean caches
- **Setup script**: `scripts/setup_python.sh` - auto-install Python deps

### Added - Live Examples
- `examples/api_demo.exs` - works instantly, no Python needed
- `examples/json_live.exs` - live Python json module
- `examples/numpy_math.exs` - live NumPy (626 functions discovered!)
- `example_helpers.exs` - auto-manages Python dependencies

### Added - Documentation
- `docs/20251026/COMPLETE_USAGE_EXAMPLE.md` - comprehensive guide
- `docs/20251026/AI_AGENT_ADAPTER_GENERATION.md` - future automation architecture
- `docs/20251026/BASE_FUNCTIONALITY_ROADMAP.md` - development roadmap
- `docs/20251026/SNAKEBRIDGE_VS_RAW_SNAKEPIT.md` - value proposition

### Fixed
- All 54 broken tests now passing (100% test coverage)
- Generator now calls Runtime instead of placeholders
- Schema.Differ recursive diffing
- TypeSystem.Mapper smart capitalization (dspy → DSPy)
- Cache filesystem persistence
- Compiler warnings eliminated

### Changed
- Runtime uses generic `call_python` tool (was library-specific `call_dspy`)
- SnakepitMock supports both old and new tool names
- Development mode uses mocks by default (fast iteration)

### Test Results
- 76 Elixir tests passing ✅
- 12 Python tests passing ✅
- 6 integration tests passing ✅
- **88 total tests, 100% pass rate**

## [0.1.0] - 2025-10-25

### Added
- Initial release
- Core configuration schema
- Type system mapper
- Basic code generation
- Discovery framework

[Unreleased]: https://github.com/nshkrdotcom/snakebridge/compare/v0.2.3...HEAD
[0.2.3]: https://github.com/nshkrdotcom/snakebridge/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/nshkrdotcom/snakebridge/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/nshkrdotcom/snakebridge/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/nshkrdotcom/snakebridge/releases/tag/v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/snakebridge/releases/tag/v0.1.0
