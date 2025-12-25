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
   python: [
     strategy: :uv,
     cache_dir: "priv/snakepit/python",
     platform: :auto
   ],
   lazy_generation: :on,
   usage_scan: :compile,
   generate: [functions: :used, classes: :used],
   docs: :on_demand,
   docs_cache_dir: "priv/snakepit/docs",
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
- `usage_scan`: `:compile` | `:runtime` | `:both`
- `generate`: rules for functions/classes to generate
- `docs`: `:on_demand` | `:full` | `:none`
- `docs_cache_dir`: where to store on-demand docs pages
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

### Docs Policies

- `:on_demand` builds per-symbol HTML only when requested.
- `:full` builds full docs for all generated symbols.
- `:none` disables doc generation.

### Prune Policies

- `:manual` means no automatic deletion, but `mix snakepit.prune` is available.
- `:auto` prunes unused wrappers at compile time.
- `:off` prevents any pruning, even when requested.

## Compatibility Notes

- `lazy_generation: :on` requires a usage scanner; default is `:compile`.
- When `docs: :on_demand`, `mix docs` should only include Snakepit base modules.
- `registry` can be set to `:local` for offline development.

