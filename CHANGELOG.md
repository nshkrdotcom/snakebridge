# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- (no changes yet)

## [0.5.0] - 2025-12-25

### Added
- `SnakeBridge.PythonEnv` module for Python environment orchestration
- `SnakeBridge.EnvironmentError` for missing package errors
- `SnakeBridge.IntrospectionError` for classified introspection failures
- `mix snakebridge.setup` task for provisioning Python packages
- Config options: `pypi_package`, `extras` per library
- Config option: `auto_install` (:never | :dev | :always)
- Strict mode enforcement via `SNAKEBRIDGE_STRICT=1` or `strict: true`
- Package identity in `snakebridge.lock` (`python_packages`, `python_packages_hash`)

### Changed
- Compiler now calls `PythonEnv.ensure!/1` before introspection (when not strict)
- Improved introspection error messages with fix suggestions

### Dependencies
- Requires snakepit ~> 0.7.5 (for PythonPackages support)

## [0.4.0] - 2025-12-25

### Added
- Compile-time pre-pass pipeline (scan -> introspect -> generate) with manifest + lockfile.
- Deterministic source output: one file per library under `lib/snakebridge_generated/*.ex`, committed to git.
- Snakepit-aligned runtime helpers (`snakebridge.call` / `snakebridge.stream`) and runtime client override for tests.
- Snakepit-backed Python execution for introspection and docs.
- Lockfile environment identity recorded from Snakepit runtime (version, platform, hash).
- Discovery metadata for classes and submodules, including deterministic regeneration.
- Example projects updated/added for v3 (`examples/math_demo`, `examples/proof_pipeline`).

### Changed
- Library configuration now lives in dependency options (`mix.exs`), not `config/*.exs`.
- Generated specs return `{:ok, term()} | {:error, Snakepit.Error.t()}` and use `Snakepit.PyRef`/`Snakepit.ZeroCopyRef`.
- Doc search now ranks results using discovery metadata.
- Runtime behavior is fully delegated to Snakepit; SnakeBridge stays compile-time only.

### Removed
- Legacy v2 mix tasks (`snakebridge.gen`, `list`, `info`, `clean`, `remove`) and registry-driven CLI flow.
- Multi-file adapter output under `lib/snakebridge/adapters/`.
- Auto-gitignore behavior for generated bindings.

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

[0.5.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/snakebridge/releases/tag/v0.1.0
