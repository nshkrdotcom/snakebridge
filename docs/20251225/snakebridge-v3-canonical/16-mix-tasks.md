# Mix Tasks Reference

This document lists all SnakeBridge CLI tasks, their options, and examples.

## `mix snakebridge.generate`

Generate adapters for detected usage.

Options:

- `--force` regenerate all symbols
- `--from PATH` scan a specific path (default: `lib/`)
- `--library LIB` generate only a specific library

Examples:

```bash
mix snakebridge.generate
mix snakebridge.generate --force
mix snakebridge.generate --from lib/my_app
mix snakebridge.generate --library numpy
```

## `mix snakebridge.scan`

Run the AST scanner and report detected symbols.

Options:

- `--verbose` include file/line output
- `--format json` machine-readable output
- `--paths path1,path2` override scan paths
- `--exclude pattern1,pattern2` glob patterns to exclude

Example:

```bash
mix snakebridge.scan --verbose
```

## `mix snakebridge.analyze`

Compare detected usage to generated symbols.

Options:

- `--format json` machine-readable output
- `--include-tests` include `test/` in scan

Example:

```bash
mix snakebridge.analyze
```

## `mix snakebridge.prune`

Explicitly remove unused symbols.

Options:

- `--dry-run` preview removals
- `--library LIB` prune a single library
- `--pattern GLOB` prune functions matching a pattern
- `--keep fn1,fn2` keep specific functions
- `--include-tests` include test files in usage scan

Examples:

```bash
mix snakebridge.prune --dry-run
mix snakebridge.prune numpy
mix snakebridge.prune --pattern "fft*"
```

## `mix snakebridge.verify`

Verify that generated source matches manifest and lockfile.

Options:

- `--format json` machine-readable output

Example:

```bash
mix snakebridge.verify
```

## `mix snakebridge.repair`

Regenerate missing or corrupted symbols based on manifest.

Example:

```bash
mix snakebridge.repair
```

## `mix snakebridge.doctor`

Check environment and dependency health.

Example:

```bash
mix snakebridge.doctor
```

## `mix snakebridge.ledger`

Show dynamic calls recorded during runtime.

Example:

```bash
mix snakebridge.ledger
```

## `mix snakebridge.promote`

Promote ledger entries into the manifest and regenerate source.

Options:

- `--library LIB` promote entries for a single library
- `--all` promote everything

Example:

```bash
mix snakebridge.promote --all
```

## `mix snakebridge.lock`

Manage `snakebridge.lock`.

Options:

- `--rebuild` rebuild lockfile from current environment

Example:

```bash
mix snakebridge.lock --rebuild
```

