# SnakeBridge Configuration Streamlining - Implementation Plan

## Phase 1: Critical Fixes (Immediate)

### 1.1 Fix Introspection Timeout

**File:** `lib/snakebridge/introspector.ex`

**Current behavior:** Reads from nested `:introspector` config, defaults to 30s.

```elixir
# Lines 79-81 - CHANGE FROM:
config = Application.get_env(:snakebridge, :introspector, [])
max_concurrency = Keyword.get(config, :max_concurrency, System.schedulers_online())
timeout = Keyword.get(config, :timeout, 30_000)

# TO (support both nested and flat keys for backwards compatibility):
nested_config = Application.get_env(:snakebridge, :introspector, [])
default_timeout = Application.get_env(:snakebridge, :introspector_timeout, 120_000)
default_concurrency = Application.get_env(:snakebridge, :introspector_max_concurrency, System.schedulers_online())
max_concurrency = Keyword.get(nested_config, :max_concurrency, default_concurrency)
timeout = Keyword.get(nested_config, :timeout, default_timeout)
```

**Note:** This supports both the existing nested config and the new flat keys.

### 1.2 Make CUDA Thresholds Configurable

**File:** `lib/snakebridge/wheel_selector/config_strategy.ex`

```elixir
# Line 97-99 - CHANGE FROM:
defp cuda_variant_fallback(version) do
  normalized = normalize_cuda_version(version)
  case Integer.parse(normalized || "") do
    {value, _} when value >= 124 -> "cu124"
    {value, _} when value >= 120 -> "cu121"
    {value, _} when value >= 117 -> "cu118"
    _ -> "cpu"
  end
end

# TO:
defp cuda_variant_fallback(version) do
  thresholds = Application.get_env(:snakebridge, :cuda_thresholds, [
    {"cu124", 124},
    {"cu121", 120},
    {"cu118", 117}
  ])

  normalized = normalize_cuda_version(version)
  case Integer.parse(normalized || "") do
    {value, _} ->
      Enum.find_value(thresholds, "cpu", fn {variant, threshold} ->
        if value >= threshold, do: variant
      end)
    _ -> "cpu"
  end
end
```

### 1.3 Make PyTorch Index URL Configurable

**File:** `lib/snakebridge/wheel_selector/config_strategy.ex`

```elixir
# Line 66 - CHANGE FROM:
"https://download.pytorch.org/whl/#{variant}"

# TO:
base_url = Application.get_env(:snakebridge, :pytorch_index_base_url,
  "https://download.pytorch.org/whl/")
"#{base_url}#{variant}"
```

### 1.4 Make Session Context Defaults Configurable (ADDED)

**File:** `lib/snakebridge/session_context.ex`

```elixir
# Lines 78-79 and 101-102 - CHANGE FROM:
defstruct [
  :session_id,
  :owner_pid,
  :created_at,
  max_refs: 10_000,
  ttl_seconds: 3600,
  tags: %{}
]

# ...
max_refs: Keyword.get(opts, :max_refs, 10_000),
ttl_seconds: Keyword.get(opts, :ttl_seconds, 3600),

# TO:
defstruct [
  :session_id,
  :owner_pid,
  :created_at,
  max_refs: nil,  # Set in create/1
  ttl_seconds: nil,  # Set in create/1
  tags: %{}
]

# ...
max_refs: Keyword.get(opts, :max_refs, default_max_refs()),
ttl_seconds: Keyword.get(opts, :ttl_seconds, default_ttl_seconds()),

# Add helper functions:
defp default_max_refs do
  Application.get_env(:snakebridge, :session_max_refs, 10_000)
end

defp default_ttl_seconds do
  Application.get_env(:snakebridge, :session_ttl_seconds, 3600)
end
```

## Phase 2: Create Defaults Module

### New File: `lib/snakebridge/defaults.ex`

```elixir
defmodule SnakeBridge.Defaults do
  @moduledoc """
  Centralized defaults for all configurable values.
  """

  # Introspection
  def introspector_timeout, do: get(:introspector_timeout, 120_000)
  def introspector_max_concurrency, do: get(:introspector_max_concurrency, System.schedulers_online())

  # Wheel selector
  def pytorch_index_base_url, do: get(:pytorch_index_base_url, "https://download.pytorch.org/whl/")
  def cuda_thresholds do
    get(:cuda_thresholds, [
      {"cu124", 124},
      {"cu121", 120},
      {"cu118", 117}
    ])
  end

  # Session context
  def session_max_refs, do: get(:session_max_refs, 10_000)
  def session_ttl_seconds, do: get(:session_ttl_seconds, 3600)

  # Protocol
  def protocol_version, do: get(:protocol_version, 1)
  def min_supported_version, do: get(:min_supported_version, 1)

  # Code generation
  def variadic_max_arity, do: get(:variadic_max_arity, 8)
  def generated_dir, do: get(:generated_dir, "lib/snakebridge_generated")
  def metadata_dir, do: get(:metadata_dir, ".snakebridge")

  defp get(key, default) do
    Application.get_env(:snakebridge, key, default)
  end
end
```

## Phase 3: Update Hardcoded References

### Files to Update

1. **introspector.ex** - 2 values (timeout, concurrency)
2. **wheel_selector/config_strategy.ex** - 4 values (CUDA thresholds, URL)
3. **session_context.ex** - 2 values (max_refs, ttl_seconds) **[ADDED]**
4. **runtime.ex** - 2 values (protocol versions)
5. **generator.ex** - 2 values (reserved words, dunder mappings)
6. **manifest.ex** - 1 value (variadic_max_arity)
7. **compile/snakebridge.ex** - 2 values (reserved words, variadic_max_arity)

## Phase 4: Documentation

### 4.1 Update README

Add configuration section:

```markdown
## Configuration

```elixir
config :snakebridge,
  # Introspection timeout (ms) - increase for large modules
  introspector_timeout: 120_000,

  # PyTorch wheel source - for private mirrors
  pytorch_index_base_url: "https://my-mirror.example.com/pytorch/",

  # CUDA variant thresholds - add new versions as needed
  cuda_thresholds: [
    {"cu126", 126},  # New!
    {"cu124", 124},
    {"cu121", 120},
    {"cu118", 117}
  ],

  # Session lifecycle defaults
  session_max_refs: 10_000,      # Max refs per session
  session_ttl_seconds: 3600      # Session TTL (1 hour)
```
```

## Testing Plan

1. Test introspection with large modules (numpy, pandas)
2. Test CUDA threshold selection with various version strings
3. Test custom PyTorch index URL
4. Test session context with custom max_refs and ttl_seconds
5. Ensure backwards compatibility with no config

## Values Intentionally NOT Made Configurable

These values should remain hardcoded:

| Value | Location | Reason |
|-------|----------|--------|
| `@schema_version 1` | `types.ex`, `ref.ex` | Wire protocol version - changing breaks compatibility |
| `@reserved_words` | `generator.ex`, `compile/snakebridge.ex` | Elixir language keywords - rarely change |
| `@dunder_mappings` | `generator.ex` | Python→Elixir name mappings - stable convention |
| Telemetry buckets | `metrics.ex` | Statistical distribution buckets - advanced tuning only |
| Lock generator files | `lock.ex` | Internal implementation detail |

## Migration Notes

- All changes are additive (new config options)
- Existing deployments continue to work with defaults
- No breaking changes to public API
