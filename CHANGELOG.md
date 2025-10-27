# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- [ ] Generator support for module-level functions
- [ ] gRPC streaming support
- [ ] Configuration composition (extends, mixins)
- [ ] LSP server for config authoring
- [ ] Auto-generated test suites from schemas

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

[Unreleased]: https://github.com/nshkrdotcom/snakebridge/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/nshkrdotcom/snakebridge/releases/tag/v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/snakebridge/releases/tag/v0.1.0
