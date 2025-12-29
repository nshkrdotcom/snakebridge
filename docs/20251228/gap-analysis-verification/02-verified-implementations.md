# Verified Working Implementations

The gap analysis also claims certain features ARE implemented. All implementation claims were verified as **TRUE**.

---

## 1. Pre-Pass Compiler Pipeline

**Status:** VERIFIED TRUE

**Location:** `lib/mix/tasks/compile/snakebridge.ex`

The compiler follows the documented flow:
1. `run/1` - Entry point, checks skip flag and loads config
2. `run_with_config/1` - Dispatches to strict or normal mode
3. `run_normal/1` - Executes: scan → introspect → manifest → generate → lock

```elixir
defp run_normal(config) do
  detected = scanner_module().scan_project(config)     # Step 1: Scan
  manifest = Manifest.load(config)
  missing = Manifest.missing(manifest, detected)
  targets = build_targets(missing, config, manifest)

  updated_manifest =
    if targets != [] do
      update_manifest(manifest, targets)                # Step 2: Introspect
    else
      manifest
    end

  Manifest.save(config, updated_manifest)              # Step 3: Manifest
  generate_from_manifest(config, updated_manifest)     # Step 4: Generate
  generate_helper_wrappers(config)
  Lock.update(config)                                  # Step 5: Lock
  {:ok, []}
end
```

---

## 2. Configuration From mix.exs

**Status:** VERIFIED TRUE

**Location:** `lib/snakebridge/config.ex`

Config struct includes all documented fields:
- `libraries` - List of Library structs
- `auto_install` - `:never | :dev | :always`
- `generated_dir`, `metadata_dir`
- `helper_paths`, `helper_pack_enabled`, `helper_allowlist`
- `strict`, `verbose`
- `scan_paths`, `scan_exclude`

Library struct includes:
- `pypi_package`, `extras`
- `include`, `exclude`
- `streaming` (though not wired to generation)
- `submodules`

---

## 3. Python Environment Provisioning

**Status:** VERIFIED TRUE

**Location:** `lib/snakebridge/python_env.ex`

`PythonEnv.ensure!/1` is called in normal compile path (line 38 of compile task):
```elixir
PythonEnv.ensure!(config)
```

`mix snakebridge.setup` exists at `lib/mix/tasks/snakebridge.setup.ex` with:
- `--upgrade` flag
- `--verbose` flag
- `--check` flag (dry run)

---

## 4. Introspection Returns Structured Metadata

**Status:** VERIFIED TRUE

**Location:** `lib/snakebridge/introspector.ex:76-168`

The embedded Python script introspects:

For functions:
- `name`, `callable`, `module`, `python_module`
- `parameters` with `name`, `kind`, `default`, `annotation`
- `return_annotation`
- `docstring`

For classes:
- `name`, `type: "class"`, `python_module`
- `docstring`
- `methods` (including `__init__` with parameters)
- `attributes`

---

## 5. Manifest + Lock Persistence

**Status:** VERIFIED PARTIALLY TRUE

### Manifest: Deterministic (TRUE)

**Location:** `SnakeBridge.Manifest.sort_manifest/1`

```elixir
defp sort_manifest(manifest) do
  manifest
  |> update_in(["symbols"], fn symbols ->
    symbols
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Map.new()
  end)
  |> update_in(["classes"], fn classes ->
    classes
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Map.new()
  end)
end
```

The manifest explicitly sorts keys before serialization, ensuring deterministic output across runs and machines.

### Lock: Content Stable, Key Order NOT Guaranteed (PARTIALLY TRUE)

**Location:** `lib/snakebridge/lock.ex`

The lock file builds a comprehensive structure with:
- `version`, `environment` (including hardware and platform sections)
- `compatibility` section
- `libraries` and `python_packages` sections

**Determinism Caveat:** The lock uses `Jason.encode!(pretty: true)` without explicit key sorting. While map enumeration order may appear stable on a given OTP version, this is NOT the same as a deliberate determinism guarantee. JSON key ordering is not normalized, which can cause:
- Spurious git diffs when lock is regenerated on different machines/OTP versions
- Merge conflicts in team workflows even when semantic content is identical

**Recommendation:** For true determinism, the lock should apply recursive key sorting before JSON encoding, similar to how the manifest does.

---

## 6. Runtime Supports Full Call Surface

**Status:** VERIFIED TRUE

**Location:** `lib/snakebridge/runtime.ex`

| Function | Lines | Purpose |
|----------|-------|---------|
| `call/4` | 16-20 | Standard function call |
| `stream/5` | 40-47 | Streaming call with callback |
| `call_class/4` | 49-61 | Class instantiation |
| `call_method/4` | 63-75 | Instance method call |
| `get_attr/3` | 77-90 | Attribute getter |
| `set_attr/4` | 92-105 | Attribute setter |
| `call_helper/3` | 23-38 | Helper function call |

All support:
- `__args__` for extra positional args
- `idempotent` flag
- `__runtime__` for runtime-specific options
- Keyword arguments as kwargs

---

## 7. Docs Plumbing with ETS Caching

**Status:** VERIFIED PARTIALLY TRUE

**Location:** `lib/snakebridge/docs.ex`

- `get/2` fetches docs with cache lookup
- Uses ETS table `:snakebridge_docs`
- `lookup_cache/1` and `maybe_cache/2` handle caching
- `search/2` uses `__functions__/0` for discovery
- Configurable `source:` option (`:python`, `:metadata`, `:hybrid`)

**Important Limitation:** The `:metadata` source is a stub. `fetch_from_metadata/2` always returns `nil`:

```elixir
defp fetch_from_metadata(_module, _function) do
  nil
end
```

This means:
- `:metadata` mode always results in "Documentation unavailable."
- `:hybrid` mode behaves identically to `:python` (always falls back)
- Only `:python` source actually works

See Gap #12 in `03-partial-findings.md` for details.

---

## 8. Documentation Parsing Pipeline Exists

**Status:** VERIFIED TRUE

Three fully-implemented modules:

**RstParser** (`lib/snakebridge/docs/rst_parser.ex`):
- Detects style: `:google`, `:numpy`, `:sphinx`, `:epytext`
- Extracts: `short_description`, `long_description`, `params`, `returns`, `raises`, `examples`, `notes`
- ~630 lines of comprehensive parsing logic

**MarkdownConverter** (`lib/snakebridge/docs/markdown_converter.ex`):
- Converts parsed docs to ExDoc Markdown
- Type mapping (Python → Elixir types)
- Exception mapping
- Example conversion (doctest → iex format)

**MathRenderer** (`lib/snakebridge/docs/math_renderer.ex`):
- Converts RST `:math:` inline to `$...$`
- Converts `.. math::` blocks to `$$...$$`
- KaTeX-compatible output

**Note:** These modules exist and are complete, but are not wired into the generation pipeline (see Gap #7).

---

## 9. TypeMapper Is Comprehensive

**Status:** VERIFIED TRUE

**Location:** `lib/snakebridge/generator/type_mapper.ex`

Handles:
- Primitives: `int`, `float`, `str`, `bool`, `bytes`, `none`, `any`
- Complex: `list`, `dict`, `tuple`, `set`, `optional`, `union`, `class`
- ML-specific: `numpy.ndarray`, `torch.tensor`, `torch.Tensor`, `pandas.DataFrame`, `pandas.Series`

Each has proper Elixir typespec AST generation via `quote`.

**Note:** This module is complete but not used in generation (see Gap #8).

---

## 10. Telemetry Events Defined

**Status:** VERIFIED TRUE

**Location:** `lib/snakebridge/telemetry.ex`

Defines helpers for all documented events:
- `compile_start/2`, `compile_stop/5`, `compile_exception/3`
- `scan_stop/4`
- `introspect_start/2`, `introspect_stop/5`
- `generate_stop/6`
- `docs_fetch/4`
- `lock_verify/3`

**Handlers exist:**
- `lib/snakebridge/telemetry/handlers/logger.ex`
- `lib/snakebridge/telemetry/handlers/metrics.ex`
- `lib/snakebridge/telemetry/runtime_forwarder.ex`

**Note:** Events are defined but not emitted from compile pipeline (see Gap #10).

---

## 11. Helper Registry and Generator

**Status:** VERIFIED TRUE

**Locations:**
- `lib/snakebridge/helpers.ex`
- `lib/snakebridge/helper_generator.ex`
- `lib/snakebridge/helper_registry_error.ex`
- `lib/snakebridge/helper_not_found_error.ex`

The compile task integrates helper generation:
```elixir
defp generate_helper_wrappers(config) do
  if Helpers.enabled?(config) do
    case Helpers.discover(config) do
      {:ok, helpers} ->
        HelperGenerator.generate_helpers(helpers, config)
      ...
    end
  end
end
```

---

## 12. Additional Verified Components

### Wheel Selector
**Location:** `lib/snakebridge/wheel_selector.ex`
Exists for selecting appropriate Python wheels.

### ML Error Structs
**Locations:**
- `lib/snakebridge/error.ex`
- `lib/snakebridge/error/shape_mismatch_error.ex`
- `lib/snakebridge/error/dtype_mismatch_error.ex`
- `lib/snakebridge/error/out_of_memory_error.ex`
- `lib/snakebridge/error_translator.ex`

ML-specific error types are defined and translator exists.

### Ledger Module
**Location:** `lib/snakebridge/ledger.ex`
Exists as a thin wrapper for dynamic calls through Snakepit. Note: This is minimal compared to documented ledger/promote workflow.
