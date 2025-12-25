# Config Spec: Snakepit + Snakebridge (mix.exs)

This file defines the canonical configuration surface for the lazy ecosystem. The principle is simple: **libraries are configured directly in the Snakepit dependency**, so runtime and adapter behavior live together.

## Minimal Example

```
{:snakepit, "~> 0.4.0",
 snakebridge: [
   libraries: [sympy: "1.12", numpy: "1.26"],
   lazy_generation: :on,
   docs: :on_demand
 ]}
```

## Full Example

```
{:snakepit, "~> 0.4.0",
 snakebridge: [
   libraries: [
     sympy: "1.12",
     numpy: "1.26",
     torch: {:pip, "torch==2.1.0"},
     sklearn: {:uv, "scikit-learn==1.4.2"}
   ],
   lockfile: "snakebridge.lock",
   python: [
     strategy: :uv,
     cache_dir: "priv/snakepit/python",
     platform: :auto
   ],
   generation_mode: :prepass,
   lazy_generation: :on,
   usage_scan: :compile,
   ledger: [mode: :dev, promote: :manual],
   generate: [functions: :used, classes: :used],
   docs: :on_demand,
   docs_source: :metadata,
   docs_cache_dir: "priv/snakepit/docs",
   strict: true,
   prune: :manual,
   registry: [
     source: :hex,
     namespace: "snakepit_libs",
     allow_untrusted: false
   ]
 ]}
```

## Schema

### Top Level: `snakebridge`

- `libraries` (required): list or map of libraries to install and introspect
- `lazy_generation`: `:on` | `:off`
- `generation_mode`: `:prepass` | `:tracer` (experimental)
- `usage_scan`: `:compile` | `:runtime` | `:both`
- `ledger`: runtime usage ledger settings
- `generate`: rules for functions/classes to generate
- `docs`: `:on_demand` | `:full` | `:none`
- `docs_source`: `:metadata` | `:python` | `:hybrid`
- `docs_cache_dir`: where to store on-demand docs pages
- `lockfile`: lockfile path (default `snakebridge.lock`)
- `strict`: `true` fails builds if generation is required
- `prune`: `:manual` | `:auto` | `:off`
- `registry`: where to fetch metadata packages
- `python`: Python environment strategy and cache path

### Libraries

Libraries can be specified in three forms:

1. **Simple version**

```
libraries: [sympy: "1.12", numpy: "1.26"]
```

2. **Explicit installer**

```
libraries: [torch: {:pip, "torch==2.1.0"}]
```

3. **Full per-library config**

```
libraries: [
  sympy: [
    version: "1.12",
    generate: [functions: :used, classes: :used],
    docs: :on_demand,
    prune: :manual,
    index: :registry
  ]
]
```

### Generation Policies

- `:used` only generates wrappers for symbols detected in project usage.
- `:all` generates all symbols discovered via introspection.
- `:none` skips generation for that category.

### Usage Scan Modes

- `:compile` scans project AST at compile time.
- `:runtime` records unresolved calls and writes a usage ledger.
- `:both` uses AST scanning and runtime fallback for dynamic calls.

### Ledger Settings

```
ledger: [mode: :dev, promote: :manual]
```

- `mode`: `:off` | `:dev` | `:all`
- `promote`: `:manual` requires `mix snakepit.promote_ledger`

Ledger entries never affect builds unless explicitly promoted or `promote: :auto` is set.

### Docs Policies

- `:on_demand` builds per-symbol HTML only when requested.
- `:full` builds full docs for all generated symbols.
- `:none` disables doc generation.
  
`docs_source` controls the source of truth:

- `:metadata` uses the pinned metadata snapshot (deterministic, CI-friendly)
- `:python` queries live Python (best in dev, non-deterministic)
- `:hybrid` prefers metadata, falls back to Python in dev

### Prune Policies

- `:manual` means no automatic deletion, but `mix snakepit.prune` is available.
- `:auto` prunes unused wrappers at compile time.
- `:off` prevents any pruning, even when requested.

### Strict Mode

```
strict: true
```

When `strict: true`, compilation fails if generation would be required (CI-safe). In dev you can set `strict: false` for automatic generation.

### Lockfile

```
lockfile: "snakebridge.lock"
```

The lockfile stores environment identity and resolved library versions to guarantee deterministic generation. It should be committed.

## Compatibility Notes

- `lazy_generation: :on` requires a usage scanner; default is `:compile`.
- `generation_mode: :prepass` is the default and is deterministic.
- When `docs: :on_demand`, `mix docs` should only include Snakepit base modules.
- `registry` can be set to `:local` for offline development.
