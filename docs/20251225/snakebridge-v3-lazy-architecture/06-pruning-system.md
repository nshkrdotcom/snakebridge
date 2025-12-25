# Pruning System

## Philosophy

The cache accumulates by default. Pruning is an **explicit, intentional operation** that requires developer consent. This ensures:

1. **Deterministic builds** — The same code always compiles the same way
2. **No surprises** — Dead code doesn't randomly break CI
3. **Audit trail** — You know exactly what was removed and when
4. **Safe refactoring** — Temporary removal of code doesn't lose bindings

## Pruning Modes

### Manual Pruning (Default)

By default, the cache never auto-prunes. Developers explicitly clean up:

```bash
# Analyze what's unused
$ mix snakebridge.analyze
SnakeBridge Cache Analysis
==========================

Total entries: 156
Used in last compile: 89
Potentially unused: 67

By library:
  numpy (85 entries)
    - Used: 45
    - Unused 30+ days: 12
    - Unused 7-30 days: 28

  pandas (45 entries)
    - Used: 30
    - Unused 30+ days: 5
    - Unused 7-30 days: 10

  sympy (26 entries)
    - Used: 14
    - Unused 30+ days: 8
    - Unused 7-30 days: 4

Recommendations:
  - Consider pruning 25 entries unused for 30+ days
  - Run `mix snakebridge.prune --dry-run` to preview
```

```bash
# Preview what would be pruned
$ mix snakebridge.prune --dry-run
Would prune 25 entries:

numpy:
  - fft/1 (last used: 2025-11-20)
  - ifft/1 (last used: 2025-11-20)
  - fft2/1 (last used: 2025-11-20)
  - ...

sympy:
  - simplify/1 (last used: 2025-11-15)
  - expand/1 (last used: 2025-11-15)
  - ...

Run without --dry-run to execute.
```

```bash
# Execute pruning
$ mix snakebridge.prune
Pruning 25 entries unused for 30+ days...
  ✓ Removed 12 numpy entries
  ✓ Removed 5 pandas entries
  ✓ Removed 8 sympy entries

Cache size reduced: 2.3 MB → 1.8 MB
```

### Per-Library Pruning

```bash
# Prune specific library
$ mix snakebridge.prune numpy

# With time threshold
$ mix snakebridge.prune sympy --unused-days 7

# Keep specific functions
$ mix snakebridge.prune numpy --keep solve,dot,array
```

### Selective Pruning

```bash
# Prune by pattern
$ mix snakebridge.prune --pattern "fft*"
Would prune: fft/1, fft2/1, fftn/1, fftshift/1, ifft/1, ifft2/1

# Prune specific functions
$ mix snakebridge.prune numpy.fft/1 numpy.ifft/1
```

## Auto-Pruning (Opt-In)

For teams that want automatic cleanup, auto-pruning can be enabled:

### Global Auto-Prune

```elixir
# config/config.exs
config :snakebridge,
  auto_prune: [
    enabled: true,
    keep_days: 30,           # Keep unused entries for 30 days
    run_on: :compile,        # Prune during compilation
    environment: [:prod]     # Only in prod builds
  ]
```

### Per-Library Auto-Prune

```elixir
# mix.exs
{:snakebridge, "~> 3.0",
 libraries: [
   # No auto-prune (default)
   numpy: "~> 1.26",

   # Auto-prune after 14 days unused
   sympy: [
     version: "~> 1.12",
     prune: :auto,
     prune_keep_days: 14
   ],

   # Aggressive pruning for experimental lib
   experimental_lib: [
     version: "~> 0.1",
     prune: :auto,
     prune_keep_days: 1
   ]
 ]}
```

### CI Auto-Prune

```yaml
# .github/workflows/release.yml
jobs:
  release:
    steps:
      - name: Prune unused bindings
        run: mix snakebridge.prune --unused-days 7 --force

      - name: Build release
        run: MIX_ENV=prod mix release
```

## Programmatic API

```elixir
# Analyze cache
{:ok, analysis} = SnakeBridge.Cache.analyze()
# => %{total: 156, used_last_compile: 89, unused_30d: 25, ...}

# Prune programmatically
{:ok, pruned} = SnakeBridge.Cache.prune(unused_days: 30)
# => %{removed: 25, freed_bytes: 524288}

# Prune specific entries
SnakeBridge.Cache.remove(Numpy, :fft, 1)
SnakeBridge.Cache.remove_library(:sympy)

# Conditional pruning
SnakeBridge.Cache.prune_if(fn entry ->
  entry.library == :sympy and entry.use_count < 5
end)
```

## Safety Mechanisms

### Pre-Prune Validation

Before pruning, the system checks for potential issues:

```elixir
$ mix snakebridge.prune
Analyzing dependencies...

⚠️  Warning: Some entries to be pruned are used in test files:
  - Numpy.fft/1 used in test/signal_test.exs:45

Options:
  1. Skip these entries (recommended)
  2. Include test files in usage detection
  3. Force prune anyway

Choice [1]:
```

### Backup Before Prune

```elixir
config :snakebridge,
  prune: [
    backup: true,
    backup_dir: "_build/snakebridge/backups"
  ]
```

```bash
$ mix snakebridge.prune
Creating backup: _build/snakebridge/backups/2025-12-25_143000.tar.gz
Pruning 25 entries...
Done. Backup available for 7 days.
```

### Restore from Backup

```bash
$ mix snakebridge.restore
Available backups:
  1. 2025-12-25_143000 (25 entries, 0.5 MB)
  2. 2025-12-20_091500 (10 entries, 0.2 MB)

Restore which backup? [1]: 1
Restored 25 entries.
```

## Integration with CI/CD

### Prune on Release

```elixir
# mix.exs
defp aliases do
  [
    release: [
      "snakebridge.prune --unused-days 7 --force",
      "release"
    ]
  ]
end
```

### Separate Prune Step

```yaml
# GitHub Actions
- name: Analyze cache
  run: mix snakebridge.analyze --format json > cache_report.json

- name: Upload report
  uses: actions/upload-artifact@v3
  with:
    name: cache-report
    path: cache_report.json

- name: Prune if threshold exceeded
  run: |
    UNUSED=$(jq '.unused_30d' cache_report.json)
    if [ $UNUSED -gt 50 ]; then
      mix snakebridge.prune --unused-days 30 --force
    fi
```

## Reporting

### Usage Report

```bash
$ mix snakebridge.report
SnakeBridge Usage Report
========================
Generated: 2025-12-25 14:30:00

Cache Overview:
  Total entries: 156
  Total size: 2.3 MB
  Oldest entry: 2025-10-15 (Numpy.array/1)
  Newest entry: 2025-12-25 (Pandas.merge/4)

Usage Distribution:
  High usage (100+ calls): 12 entries
  Medium usage (10-99): 45 entries
  Low usage (1-9): 67 entries
  Never used after generation: 32 entries

Library Breakdown:
  ┌──────────┬─────────┬──────────┬────────────┐
  │ Library  │ Entries │ Size     │ Last Used  │
  ├──────────┼─────────┼──────────┼────────────┤
  │ numpy    │ 85      │ 1.2 MB   │ Today      │
  │ pandas   │ 45      │ 0.8 MB   │ Today      │
  │ sympy    │ 26      │ 0.3 MB   │ 5 days ago │
  └──────────┴─────────┴──────────┴────────────┘

Recommendations:
  • 32 entries have never been used - consider pruning
  • sympy hasn't been used in 5 days - check if still needed
```

### JSON Export

```bash
$ mix snakebridge.report --format json > report.json
```

```json
{
  "generated_at": "2025-12-25T14:30:00Z",
  "cache": {
    "total_entries": 156,
    "total_bytes": 2411724,
    "libraries": {
      "numpy": {
        "entries": 85,
        "bytes": 1258291,
        "functions": ["array", "zeros", "dot", "..."],
        "last_used": "2025-12-25T14:25:00Z"
      }
    }
  },
  "usage": {
    "high": 12,
    "medium": 45,
    "low": 67,
    "zero": 32
  },
  "recommendations": [
    {"type": "prune", "reason": "unused", "entries": 32}
  ]
}
```

## Best Practices

### Development Workflow

```
1. Develop normally - cache accumulates
2. Periodically run `mix snakebridge.analyze`
3. Before release, run `mix snakebridge.prune --unused-days 14`
4. Commit cache to git (or use CI cache)
```

### Team Workflow

```
1. Each developer has local cache
2. CI maintains shared cache
3. Releases prune to production set
4. Shared cache server syncs team (future)
```

### Monorepo Workflow

```
apps/
  app_a/  # Uses numpy
  app_b/  # Uses pandas
  shared/ # Uses both

# Per-app pruning
$ cd apps/app_a && mix snakebridge.prune

# Global pruning
$ mix snakebridge.prune --all-apps
```

## Configuration Reference

```elixir
config :snakebridge,
  prune: [
    # Auto-prune settings
    auto: false,                    # Enable auto-prune
    auto_keep_days: 30,             # Days to keep unused entries
    auto_environment: [:prod],      # Environments for auto-prune
    auto_on: :compile,              # When to auto-prune

    # Safety settings
    backup: true,                   # Backup before prune
    backup_dir: "_build/snakebridge/backups",
    backup_keep_days: 7,            # How long to keep backups

    # Analysis settings
    analyze_include_tests: true,    # Include test files in usage
    analyze_include_dev: true,      # Include dev-only code

    # Thresholds
    warn_unused_days: 14,           # Warn if unused this long
    suggest_prune_count: 20         # Suggest pruning if > N unused
  ]
```
