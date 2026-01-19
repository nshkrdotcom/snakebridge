# Configuration Reference

Complete reference for all SnakeBridge configuration options.

## Python Dependencies (mix.exs)

Configure Python libraries in your `mix.exs` project definition.

### Basic Structure

```elixir
def project do
  [
    app: :my_app,
    deps: deps(),
    python_deps: python_deps(),
    compilers: [:snakebridge] ++ Mix.compilers()
  ]
end

defp python_deps do
  [
    {:numpy, "1.26.0"},
    {:pandas, "2.0.0", include: ["DataFrame"]}
  ]
end
```

### Dependency Formats

```elixir
# Simple: name and version
{:numpy, "1.26.0"}

# With options (3-tuple)
{:pandas, "2.0.0", opts}

# Standard library (no version)
{:math, :stdlib}
{:json, :stdlib}

# Latest version (not recommended for production)
{:requests, :latest}
```

### Dependency Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pypi_package` | `String` | library name | PyPI package name if different from Elixir atom |
| `extras` | `[String]` | `[]` | pip extras (e.g., `["sql", "excel"]`) |
| `include` | `[String]` | `[]` | Only generate these symbols |
| `exclude` | `[String]` | `[]` | Exclude these symbols from generation |
| `submodules` | `boolean` | `false` | Include submodules in generation |
| `generate` | `:used \| :all` | `:used` | Generation mode |
| `streaming` | `[String]` | `[]` | Functions that get `*_stream` variants |
| `min_signature_tier` | `atom` | `nil` | Minimum signature quality threshold |
| `signature_sources` | `[atom]` | all | Allowed signature sources |
| `strict_signatures` | `boolean` | `false` | Fail on low-quality signatures |

### Generation Modes

```elixir
# :used (default) - Only generate symbols used in your code
{:numpy, "1.26.0"}

# :all - Generate all public symbols
{:pandas, "2.0.0", generate: :all}
```

### Symbol Filtering

```elixir
{:pandas, "2.0.0",
  include: ["DataFrame", "read_csv", "read_json"],  # Only these
  exclude: ["testing", "_internal"]}                 # Never these
```

### Submodule Generation

```elixir
# Generate numpy.linalg, numpy.random, etc.
{:numpy, "1.26.0", submodules: true}

# Combine with include for targeted submodules
{:numpy, "1.26.0", submodules: true, include: ["linalg", "random"]}
```

### Signature Quality

```elixir
{:pandas, "2.0.0",
  min_signature_tier: :stub,           # Require at least stub quality
  signature_sources: [:runtime, :stub], # Only use these sources
  strict_signatures: true}              # Fail compilation on violations
```

Signature tiers (highest to lowest): `:runtime`, `:text_signature`, `:runtime_hints`, `:stub`, `:stubgen`, `:variadic`

### Streaming Functions

```elixir
{:llm_lib, "1.0.0", streaming: ["generate", "complete"]}
# Generates: LlmLib.generate/2 and LlmLib.generate_stream/3
```

## Application Configuration

Configure in `config/config.exs` or environment-specific files.

### Path Configuration

```elixir
config :snakebridge,
  generated_dir: "lib/snakebridge_generated",  # Generated code location
  metadata_dir: ".snakebridge",                 # Metadata and cache
  scan_paths: ["lib"],                          # Paths to scan for usage
  scan_exclude: ["lib/generated"]               # Exclude from scanning
```

### Behavior Configuration

```elixir
config :snakebridge,
  auto_install: :dev_test,  # :never | :dev | :dev_test | :always
  strict: false,            # Strict mode for CI
  verbose: false            # Verbose compilation output
```

### Error Handling

```elixir
config :snakebridge,
  error_mode: :raw  # :raw | :translated | :raise_translated
```

| Mode | Behavior |
|------|----------|
| `:raw` | Return Python errors as-is |
| `:translated` | Translate to structured Elixir errors |
| `:raise_translated` | Raise translated errors as exceptions |

### Type System

```elixir
config :snakebridge,
  atom_allowlist: ["ok", "error", "true", "false"]  # Safe atoms to decode
```

### Introspection

```elixir
config :snakebridge, :introspector,
  max_concurrency: 4,    # Parallel introspection workers
  timeout: 30_000        # Introspection timeout (ms)
```

### Documentation

```elixir
config :snakebridge, :docs,
  cache_enabled: true,   # Cache parsed docs
  cache_ttl: :infinity,  # Cache duration
  source: :python        # :python | :metadata
```

### Coverage Reports

```elixir
config :snakebridge,
  coverage_report: [
    output_dir: ".snakebridge/coverage",
    format: [:json, :markdown]
  ]
```

### Stub Configuration

```elixir
config :snakebridge,
  stub_search_paths: ["priv/python/stubs"],
  use_typeshed: true
```

### Variadic Arities

```elixir
config :snakebridge,
  variadic_max_arity: 8  # Max arity for variadic fallback wrappers
```

## Runtime Configuration

Configure in `config/runtime.exs` for dynamic settings.

### Basic Setup

```elixir
import Config
SnakeBridge.ConfigHelper.configure_snakepit!()
```

### Pool Configuration

```elixir
SnakeBridge.ConfigHelper.configure_snakepit!(
  pool_size: 4,                    # Workers per pool
  affinity: :strict_queue,         # Default affinity mode
  venv_path: "/path/to/venv"       # Explicit venv location
)
```

### Multi-Pool Setup

```elixir
SnakeBridge.ConfigHelper.configure_snakepit!(
  pools: [
    %{name: :cpu_pool, pool_size: 4, affinity: :hint},
    %{name: :gpu_pool, pool_size: 2, affinity: :strict_queue}
  ]
)
```

### Timeout Profiles

```elixir
config :snakebridge,
  runtime: [
    timeout_profile: :default,
    default_timeout: 120_000,
    default_stream_timeout: 1_800_000,

    library_profiles: %{
      "transformers" => :ml_inference,
      "torch" => :batch_job
    },

    profiles: %{
      default: [timeout: 120_000],
      ml_inference: [timeout: 600_000, stream_timeout: 1_800_000],
      batch_job: [timeout: :infinity, stream_timeout: :infinity]
    }
  ]
```

### Session Configuration

```elixir
config :snakebridge,
  session_max_refs: 10_000,        # Max refs per session
  session_ttl_seconds: 3600,       # Session TTL (1 hour)
  session_cleanup_log_level: :debug # Optional cleanup logging
```

## Environment Variables

### Compile-time

| Variable | Default | Description |
|----------|---------|-------------|
| `SNAKEBRIDGE_STRICT` | `0` | Enable strict mode (`1` to enable) |
| `SNAKEBRIDGE_VERBOSE` | `0` | Enable verbose output |

### Runtime (Python Adapter)

| Variable | Default | Description |
|----------|---------|-------------|
| `SNAKEBRIDGE_REF_TTL_SECONDS` | `0` | Ref TTL (0 = disabled) |
| `SNAKEBRIDGE_REF_MAX` | `10000` | Max refs in registry |
| `SNAKEBRIDGE_ATOM_CLASS` | `false` | Use Atom wrapper class |
| `SNAKEBRIDGE_ALLOW_LEGACY_PROTOCOL` | `0` | Accept legacy payloads |

### Snakepit Integration

| Variable | Default | Description |
|----------|---------|-------------|
| `SNAKEBRIDGE_VENV` | auto | Explicit venv path |
| `SNAKEPIT_LOG_LEVEL` | `error` | Python-side log level |
| `SNAKEPIT_SCRIPT_EXIT` | `auto` | Script exit mode |

## Runtime Options (__runtime__)

Pass to any call via the `__runtime__:` key.

```elixir
SnakeBridge.call("module", "fn", [args],
  __runtime__: [
    session_id: "custom-session",
    timeout: 60_000,
    timeout_profile: :ml_inference,
    stream_timeout: 300_000,
    affinity: :strict_queue,
    pool_name: :gpu_pool,
    idempotent: true
  ]
)
```

| Option | Type | Description |
|--------|------|-------------|
| `session_id` | `String` | Use specific session |
| `timeout` | `integer` | Call timeout (ms) |
| `timeout_profile` | `atom` | Named timeout profile |
| `stream_timeout` | `integer` | Streaming timeout (ms) |
| `affinity` | `atom` | Worker affinity mode |
| `pool_name` | `atom` | Target worker pool |
| `idempotent` | `boolean` | Enable response caching |

## Wheel Variants

Configure hardware-specific wheels in `config/wheel_variants.json`:

```json
{
  "packages": {
    "torch": {
      "variants": ["cpu", "cu118", "cu121", "cu124"]
    }
  },
  "cuda_mappings": {
    "12.1": "cu121",
    "12.4": "cu124"
  }
}
```

Override in config:

```elixir
config :snakebridge,
  wheel_config_path: "config/wheel_variants.json",
  wheel_strategy: SnakeBridge.WheelSelector.ConfigStrategy
```

## See Also

- [Getting Started](GETTING_STARTED.md) - Initial setup
- [Generated Wrappers](GENERATED_WRAPPERS.md) - Code generation details
- [Session Affinity](SESSION_AFFINITY.md) - Affinity mode details
- [Coverage Reports](COVERAGE_REPORTS.md) - Coverage reporting
