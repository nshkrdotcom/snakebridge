# Configuration

## Quick Start

```elixir
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 3.0",
     libraries: [
       numpy: "~> 1.26",
       pandas: "~> 2.0"
     ]}
  ]
end
```

That's it. Libraries are declared in the dependency itself.

## Library Declaration

### Simple Version

```elixir
libraries: [
  numpy: "~> 1.26",
  sympy: "~> 1.12",
  json: :stdlib     # Python stdlib, no version needed
]
```

### With Options

```elixir
libraries: [
  numpy: [
    version: "~> 1.26",
    module_name: Np,              # Custom Elixir module name
    python_name: "numpy",         # Python import name (default: atom as string)
    include: ["array", "zeros"],  # Allowlist (skip scan, generate these)
    exclude: ["deprecated_fn"]    # Blocklist (never generate)
  ],
  
  # Short form with options
  pandas: [version: "~> 2.0", module_name: Pd]
]
```

## Compiler Configuration

```elixir
# mix.exs
def project do
  [
    compilers: [:snakebridge] ++ Mix.compilers(),
    # ...
  ]
end
```

The `:snakebridge` compiler **must** run before the Elixir compiler.

## Application Configuration

```elixir
# config/config.exs
config :snakebridge,
  # Generation output directory
  generated_dir: "lib/snakebridge_generated",
  
  # Metadata storage
  metadata_dir: ".snakebridge",
  
  # Verbose compilation output
  verbose: false

# config/dev.exs
config :snakebridge,
  verbose: true

# config/prod.exs  
config :snakebridge,
  # Fail if generation would be needed (CI safety)
  strict: true
```

## Strict Mode

Strict mode prevents unexpected generation in CI/production:

```elixir
config :snakebridge, strict: true
```

Effects:
- **Fail** if any detected symbol is not in manifest
- **Fail** if manifest symbols don't exist in generated source
- **Succeed** only if generated source exactly matches needs

Use in CI:

```yaml
# .github/workflows/ci.yml
jobs:
  build:
    env:
      SNAKEBRIDGE_STRICT: "true"
    steps:
      - run: mix compile --warnings-as-errors
```

## Environment Variables

| Variable | Effect |
|----------|--------|
| `SNAKEBRIDGE_STRICT` | Enable strict mode |
| `SNAKEBRIDGE_VERBOSE` | Enable verbose output |
| `SNAKEBRIDGE_SKIP` | Skip generation entirely |

## Full Configuration Reference

```elixir
# mix.exs - Dependency options
{:snakebridge, "~> 3.0",
 # Required: Libraries to generate bindings for
 libraries: [
   numpy: "~> 1.26",                    # Simple: name + version
   json: :stdlib,                        # Stdlib module
   mylib: [                              # Full options
     version: "~> 1.0",
     module_name: MyLib,                 # Elixir module (default: Camelize)
     python_name: "my_lib",              # Python import (default: atom as string)
     include: ["fn1", "fn2"],            # Only generate these
     exclude: ["deprecated"],            # Never generate these
     submodules: true                    # Generate submodule bindings
   ]
 ],
 
 # Optional: Override output paths
 generated_dir: "lib/snakebridge_generated",
 metadata_dir: ".snakebridge"
}
```

```elixir
# config/config.exs - Runtime configuration
config :snakebridge,
  # Compilation
  verbose: false,                       # Log generation progress
  strict: false,                        # Fail if generation needed
  
  # Scanning
  scan_paths: ["lib"],                  # Paths to scan for usage
  scan_exclude: [],                     # Patterns to exclude from scan
  
  # Documentation
  docs: [
    cache_enabled: true,                # Cache doc queries
    cache_ttl: :infinity,               # Cache TTL
    source: :python                     # :python | :metadata
  ],
  
  # Pruning
  pruning: [
    warn_unused_days: 30,               # Warn if unused this long
    backup_before_prune: true           # Backup before pruning
  ]
```

## Per-Environment Patterns

### Development

```elixir
# config/dev.exs
config :snakebridge,
  verbose: true,
  strict: false
```

### Test

```elixir
# config/test.exs
config :snakebridge,
  strict: false  # Allow regeneration in test
```

### Production/CI

```elixir
# config/prod.exs
config :snakebridge,
  strict: true,
  verbose: false
```

## Snakepit Configuration

SnakeBridge uses Snakepit for runtime. Configure Snakepit separately:

```elixir
# config/config.exs
config :snakepit,
  pooling_enabled: true,
  pool_size: 10,
  adapter_module: Snakepit.Adapters.GRPCPython

# See Snakepit documentation for full options:
# https://hexdocs.pm/snakepit
```

## Configuration Loading Order

1. Compile-time defaults
2. `config/config.exs`
3. `config/#{Mix.env()}.exs`
4. Environment variables
5. mix.exs dependency options (highest priority for libraries)

## Validating Configuration

```bash
$ mix snakebridge.doctor
SnakeBridge Configuration Check
================================

Libraries:
  ✓ numpy ~> 1.26 → Numpy
  ✓ pandas ~> 2.0 → Pandas  
  ✓ sympy ~> 1.12 → Sympy

Paths:
  ✓ Generated: lib/snakebridge_generated/
  ✓ Metadata: .snakebridge/

Dependencies:
  ✓ snakepit 0.7.3 installed
  ✓ Python 3.11.5 available
  ✓ uv 0.1.24 available

Status: Ready
```
