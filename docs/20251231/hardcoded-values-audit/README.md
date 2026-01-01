# SnakeBridge Hardcoded Values Audit

**Date:** 2025-12-31
**Status:** Audit Complete
**Total Hardcoded Values Found:** 34

## Executive Summary

This audit identified **34 hardcoded values** across the snakebridge codebase. Key issues:

1. **Introspection timeout (30s)** - May be insufficient for large Python modules
2. **CUDA version thresholds** - Need updating for new CUDA versions
3. **PyTorch index URL** - Blocks private mirror usage

## Critical Issues

### 1. Introspection Timeout

**File:** `lib/snakebridge/introspector.ex:81`
**Current:** `30_000` ms
**Impact:** Large Python modules may fail to introspect.

```elixir
timeout = Keyword.get(config, :timeout, 30_000)
```

**Recommended:** Make configurable, default to `120_000` or higher.

### 2. CUDA Version Thresholds (Outdated)

**File:** `lib/snakebridge/wheel_selector/config_strategy.ex:97-99`

```elixir
# Current hardcoded values will be outdated as CUDA evolves
{value, _} when value >= 124 -> "cu124"
{value, _} when value >= 120 -> "cu121"
{value, _} when value >= 117 -> "cu118"
```

**Impact:** New CUDA versions (125, 126, etc.) require code changes.

### 3. PyTorch Index URL

**File:** `lib/snakebridge/wheel_selector/config_strategy.ex:66`

```elixir
"https://download.pytorch.org/whl/#{variant}"
```

**Impact:** Cannot use private mirrors or air-gapped environments.

### 4. Session Context Defaults (MISSING FROM ORIGINAL AUDIT)

**File:** `lib/snakebridge/session_context.ex:78-79,101-102`

```elixir
defstruct [
  # ...
  max_refs: 10_000,
  ttl_seconds: 3600,
  # ...
]
```

**Impact:** Session limits are hardcoded in struct, not configurable via Application.get_env.
Users can override per-call but cannot set system-wide defaults.

## All Hardcoded Values

| Category | Count | Priority |
|----------|-------|----------|
| Timeouts | 1 | HIGH |
| CUDA Thresholds | 3 | HIGH |
| URLs | 1 | HIGH |
| Session Defaults | 2 | HIGH (struct defaults, not app-configurable) |
| Protocol Versions | 2 | MEDIUM |
| Schema Versions | 2 | LOW (should stay fixed) |
| Max Arity | 3 | LOW (already configurable) |
| Paths | 4 | LOW (already configurable) |
| Reserved Words | 2 | LOW |
| Dunder Mappings | 1 | LOW |
| Telemetry Buckets | 1 | LOW |
| Lock Generator Files | 1 | LOW |
| Other | 11 | LOW |

## Values Already Configurable

These are already exposed via `Application.get_env/3`:

- `:generated_dir` - Default: `"lib/snakebridge_generated"`
- `:metadata_dir` - Default: `".snakebridge"`
- `:helper_paths` - Default: `["priv/python/helpers"]`
- `:scan_paths` - Default: `["lib"]`
- `:variadic_max_arity` - Default: `8`
- `:helper_pack_enabled` - Default: `true`
- `:helper_allowlist` - Default: `:all`
- `:inline_enabled` - Default: `false`

## Recommended New Configuration Options

```elixir
config :snakebridge,
  # Introspection settings (flat keys for simplicity)
  introspector_timeout: 120_000,              # was 30_000
  introspector_max_concurrency: 4,            # was System.schedulers_online()

  # Wheel selector settings
  pytorch_index_base_url: "https://download.pytorch.org/whl/",
  cuda_thresholds: [
    {"cu124", 124},
    {"cu121", 120},
    {"cu118", 117}
  ],

  # Session lifecycle settings [ADDED]
  session_max_refs: 10_000,
  session_ttl_seconds: 3600,

  # Protocol settings
  protocol_version: 1,
  min_supported_version: 1
```

**Note:** Changed from nested config (`:introspector`, `:wheel_selector`) to flat keys
for consistency with existing config patterns in the codebase.

## Files to Modify

See [implementation-plan.md](implementation-plan.md) for detailed changes.
