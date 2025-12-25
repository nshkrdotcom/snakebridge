# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2025-12-24

### Added
- **Complete v2 Rewrite** - Ground-up rebuild focused on code generation
- **Multi-file generation** - Generates organized directory structures instead of monolithic files
  - `lib/snakebridge/adapters/<library>/_meta.ex` - Discovery functions
  - `lib/snakebridge/adapters/<library>/<library>.ex` - Main module
  - `lib/snakebridge/adapters/<library>/classes/*.ex` - Class modules
- **Discovery functions** in every generated module
  - `__functions__/0` - List all functions with arities and docs
  - `__classes__/0` - List all classes with docs
  - `__submodules__/0` - List all submodules
  - `__search__/1` - Search functions by name or documentation
- **Registry system** (`SnakeBridge.Registry`) - Tracks all generated adapters
  - `list_libraries/0`, `get/1`, `generated?/1`
  - Persists to `priv/snakebridge/registry.json`
- **New mix tasks**
  - `mix snakebridge.gen <library>` - Generate adapter with multi-file output
  - `mix snakebridge.list` - List all generated adapters
  - `mix snakebridge.info <library>` - Show adapter details
  - `mix snakebridge.clean <library>` - Remove generated adapter
- **Type system** with tagged JSON serialization for lossless round-trips
  - Handles tuples, sets, datetime, bytes, infinity, NaN
- **Python introspection** respects `__all__` for public API detection
- **221 tests** with comprehensive coverage

### Changed
- Architecture changed from manifest-driven to source-generation
- Generator now outputs directories instead of single files
- Elixir naming: Python `E1` → `e1`, `acos` class → `Acos` module
- Parameter sanitization: `_` → `arg0`, `_foo` → `foo`

### Removed
- Manifest system (JSON configs, registry of manifests)
- Agent/AI-based adapter creation
- Runtime module generation (now compile-time only)
- All v1 code archived to `*_old/` directories

## [0.3.2] - 2025-12-23

### Added
- Zero-friction Python integration with auto venv/pip
- Automated adapter creation with `mix snakebridge.adapter.create`

## [0.3.1] - 2025-12-23

### Changed
- Manifest as single source of truth
- Bridges relocated to `priv/python/bridges/`

## [0.3.0] - 2025-12-23

### Added
- Manifest-driven workflow with mix tasks
- Built-in manifests for sympy, pylatexenc, math-verify
- Snakepit auto-start launcher

## [0.2.0] - 2025-10-26

### Added
- Live Python integration with generic adapter
- Public API: discover, generate, integrate
- Mix tasks for discovery and generation

## [0.1.0] - 2025-10-25

### Added
- Initial release
- Core configuration schema
- Type system mapper
- Basic code generation

[0.4.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/snakebridge/releases/tag/v0.1.0
