# Pruning System

## Philosophy

The cache accumulates by default. Pruning is an **explicit, intentional operation** that requires developer consent. This ensures:

1. **Deterministic builds** — Same code always compiles the same way
2. **No surprises** — Removing a function temporarily doesn't break CI
3. **Audit trail** — You know exactly what was removed and when
4. **Safe refactoring** — Experiment without fear of losing bindings

## Manual Pruning (Default)

By default, the cache never auto-prunes. Developers explicitly clean up:

```bash
# Analyze what's potentially unused
$ mix snakebridge.analyze
SnakeBridge Cache Analysis
==========================

Generated: 15 symbols
Detected in code: 12 symbols
Potentially unused: 3 symbols

  numpy.ex:
    - fft/1          (not detected in current scan)
    - ifft/1         (not detected in current scan)
    - fft2/1         (not detected in current scan)

Recommendations:
  - Run `mix snakebridge.prune --dry-run` to preview removal
```

### Preview Pruning

```bash
$ mix snakebridge.prune --dry-run
Would prune 3 symbols:

  numpy.ex:
    - Numpy.fft/1
    - Numpy.ifft/1
    - Numpy.fft2/1

Run without --dry-run to execute.
```

### Execute Pruning

```bash
$ mix snakebridge.prune
Pruning 3 symbols...
  ✓ Removed Numpy.fft/1
  ✓ Removed Numpy.ifft/1
  ✓ Removed Numpy.fft2/1

Regenerated numpy.ex
Updated manifest
Commit the changes.
```

## Selective Pruning

### By Library

```bash
$ mix snakebridge.prune numpy
```

### By Pattern

```bash
$ mix snakebridge.prune --pattern "fft*"
Would prune: fft/1, fft2/1, fftn/1, fftshift/1, ifft/1, ifft2/1
```

### Specific Functions

```bash
$ mix snakebridge.prune Numpy.fft/1 Numpy.ifft/1
```

### Keep Specific

```bash
$ mix snakebridge.prune numpy --keep array,zeros,mean
```

## Safety Mechanisms

### Pre-Prune Validation

```bash
$ mix snakebridge.prune
Analyzing dependencies...

⚠️  Warning: Some symbols to be pruned are used in test files:
  - Numpy.fft/1 used in test/signal_test.exs:45

Options:
  1. Skip these (recommended)
  2. Include test files in scan
  3. Force prune anyway

Choice [1]:
```

### Backup Before Prune

```elixir
config :snakebridge,
  pruning: [
    backup: true,
    backup_dir: ".snakebridge/backups"
  ]
```

```bash
$ mix snakebridge.prune
Creating backup: .snakebridge/backups/2025-12-25_143000.json
Pruning 3 symbols...
Done. Backup available.
```

### Restore from Backup

```bash
$ mix snakebridge.restore
Available backups:
  1. 2025-12-25_143000 (3 symbols)
  2. 2025-12-20_091500 (1 symbol)

Restore which backup? [1]: 1
Restoring...
  ✓ Added Numpy.fft/1
  ✓ Added Numpy.ifft/1
  ✓ Added Numpy.fft2/1
Regenerating numpy.ex...
Done.
```

## Auto-Pruning (Opt-In)

For teams that want automatic cleanup:

```elixir
config :snakebridge,
  pruning: [
    auto: true,
    auto_on: :compile,              # Prune during compilation
    auto_environment: [:prod]       # Only in prod builds
  ]
```

> [!CAUTION]
> Auto-pruning can cause non-deterministic builds if different code paths
> are exercised. Use with caution. Manual pruning is recommended.

## Programmatic API

```elixir
# Analyze cache
{:ok, analysis} = SnakeBridge.Cache.analyze()
# => %{total: 15, detected: 12, unused: 3}

# Prune specific symbols
SnakeBridge.Cache.remove(Numpy, :fft, 1)

# Prune by condition
SnakeBridge.Cache.prune_if(fn entry ->
  entry.module == Numpy and String.starts_with?(to_string(entry.function), "fft")
end)
```

## CI Integration

### Prune on Release

```elixir
# mix.exs
defp aliases do
  [
    release: [
      "snakebridge.prune --detected-only",  # Only keep detected
      "release"
    ]
  ]
end
```

### Verify No Unused Symbols

```yaml
# .github/workflows/ci.yml
- name: Check for unused generated symbols
  run: |
    mix snakebridge.analyze --format json > analysis.json
    UNUSED=$(jq '.unused' analysis.json)
    if [ "$UNUSED" -gt 0 ]; then
      echo "::warning::$UNUSED unused generated symbols"
    fi
```

## Reporting

```bash
$ mix snakebridge.report
SnakeBridge Cache Report
========================

Total symbols: 15
By library:
  numpy (10 symbols)
    Most used: array/1, mean/1, std/1
    Unused: fft/1, ifft/1, fft2/1
  pandas (5 symbols)
    All in use

Recommendations:
  - 3 symbols can be pruned (run: mix snakebridge.prune --dry-run)
```

## Configuration Reference

```elixir
config :snakebridge,
  pruning: [
    # Auto-prune (not recommended)
    auto: false,
    auto_on: :compile,
    auto_environment: [:prod],

    # Safety
    backup: true,
    backup_dir: ".snakebridge/backups",

    # Analysis
    include_test_files: false,      # Include test/ in scan
    warn_on_unused: true            # Warn during compile
  ]
```
