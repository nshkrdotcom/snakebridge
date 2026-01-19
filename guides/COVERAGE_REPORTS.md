# Coverage Reports

SnakeBridge generates coverage reports showing signature quality and documentation coverage for generated wrappers.

## Overview

Coverage reports help you understand:
- How many symbols have high-quality signatures vs variadic fallbacks
- Documentation coverage across your generated libraries
- Which symbols might need manual `.pyi` stubs

## Enabling Coverage Reports

Configure in `config/config.exs`:

```elixir
config :snakebridge,
  coverage_report: [
    output_dir: ".snakebridge/coverage",
    format: [:json, :markdown]
  ]
```

Reports are generated during compilation when using `generate: :all` mode:

```elixir
defp python_deps do
  [{:pandas, "2.0.0", generate: :all}]
end
```

## Report Formats

### JSON Report

Machine-readable format at `.snakebridge/coverage/<library>.json`:

```json
{
  "library": "pandas",
  "version": "2.0.0",
  "generated_at": "2024-01-15T10:30:00Z",
  "summary": {
    "total_symbols": 245,
    "functions": 180,
    "classes": 45,
    "constants": 20
  },
  "signature_coverage": {
    "runtime": 120,
    "text_signature": 15,
    "runtime_hints": 8,
    "stub": 42,
    "stubgen": 10,
    "variadic": 50
  },
  "doc_coverage": {
    "documented": 198,
    "undocumented": 47,
    "percentage": 80.8
  },
  "symbols": [
    {
      "name": "DataFrame",
      "type": "class",
      "signature_tier": "runtime",
      "has_docs": true,
      "methods": [...]
    }
  ]
}
```

### Markdown Report

Human-readable format at `.snakebridge/coverage/<library>.md`:

```markdown
# Coverage Report: pandas 2.0.0

Generated: 2024-01-15 10:30:00

## Summary

| Metric | Count |
|--------|-------|
| Total Symbols | 245 |
| Functions | 180 |
| Classes | 45 |
| Constants | 20 |

## Signature Coverage

| Tier | Count | Percentage |
|------|-------|------------|
| runtime | 120 | 49.0% |
| text_signature | 15 | 6.1% |
| runtime_hints | 8 | 3.3% |
| stub | 42 | 17.1% |
| stubgen | 10 | 4.1% |
| variadic | 50 | 20.4% |

**Non-Variadic Coverage: 79.6%**

## Documentation Coverage

- Documented: 198 (80.8%)
- Undocumented: 47 (19.2%)

## Symbols by Tier

### variadic (50 symbols)

These symbols have no signature information and use variadic fallbacks:

- `_internal_helper`
- `deprecated_function`
- ...
```

## Signature Tiers

SnakeBridge uses a 6-tier system for signature quality:

| Tier | Source | Quality |
|------|--------|---------|
| `runtime` | `inspect.signature()` + `get_type_hints()` | Highest |
| `text_signature` | `__text_signature__` attribute | High |
| `runtime_hints` | `__annotations__` only | Medium |
| `stub` | `.pyi` stub files | Medium |
| `stubgen` | Generated via mypy.stubgen | Lower |
| `variadic` | No signature available | Lowest |

### Non-Variadic Coverage

The key metric is **non-variadic coverage** - the percentage of symbols with actual signature information:

```
Non-Variadic = (Total - Variadic) / Total * 100
```

Target 80%+ for production libraries.

## Improving Coverage

### Add Stub Files

Create `.pyi` stubs for symbols without signatures:

```elixir
config :snakebridge,
  stub_search_paths: ["priv/python/stubs"]
```

```python
# priv/python/stubs/my_library.pyi
def my_function(arg1: str, arg2: int = 0) -> bool: ...
```

### Use Typeshed

Enable community stubs for standard library and popular packages:

```elixir
config :snakebridge,
  use_typeshed: true
```

### Constrain Signature Sources

Only use high-quality sources:

```elixir
{:pandas, "2.0.0",
  signature_sources: [:runtime, :stub],
  min_signature_tier: :stub}
```

## Strict Mode

Fail compilation when coverage falls below thresholds:

```elixir
{:pandas, "2.0.0",
  generate: :all,
  strict_signatures: true,
  min_signature_tier: :stub}
```

Or via environment variable:

```bash
SNAKEBRIDGE_STRICT=1 mix compile
```

## CI Integration

### Check Coverage in CI

```yaml
# .github/workflows/ci.yml
- name: Check signature coverage
  run: |
    mix compile
    # Parse JSON report and check thresholds
    jq '.signature_coverage.variadic < 50' .snakebridge/coverage/pandas.json
```

### Artifact Upload

```yaml
- name: Upload coverage reports
  uses: actions/upload-artifact@v3
  with:
    name: snakebridge-coverage
    path: .snakebridge/coverage/
```

## Interpreting Results

### Good Coverage

```
Non-Variadic Coverage: 92%
Documentation: 85%

Signature Tiers:
  runtime: 70%
  stub: 22%
  variadic: 8%
```

Most symbols have runtime signatures, stubs fill gaps, few variadics.

### Poor Coverage

```
Non-Variadic Coverage: 45%
Documentation: 30%

Signature Tiers:
  runtime: 20%
  stubgen: 25%
  variadic: 55%
```

Indicates C-extension library without stubs. Consider:
1. Adding custom `.pyi` stubs
2. Using `include` to limit to well-typed symbols
3. Using Universal FFI for dynamic calls

## Example: Coverage Report Workflow

```elixir
# mix.exs
defp python_deps do
  [
    {:pandas, "2.0.0",
      generate: :all,
      submodules: true,
      min_signature_tier: :stub,
      strict_signatures: Mix.env() == :prod}
  ]
end

# config/config.exs
config :snakebridge,
  coverage_report: [
    output_dir: ".snakebridge/coverage",
    format: [:json, :markdown]
  ],
  stub_search_paths: ["priv/python/stubs"],
  use_typeshed: true
```

Run compilation:

```bash
mix compile
cat .snakebridge/coverage/pandas.md
```

## See Also

- [Generated Wrappers](GENERATED_WRAPPERS.md) - Signature tier details
- [Configuration](CONFIGURATION.md) - All coverage options
- `examples/coverage_report_example` - Runnable example
