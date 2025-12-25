# Configuration System

## Overview

SnakeBridge v3 consolidates all Python library configuration into the dependency declaration itself, eliminating separate config files and reducing cognitive overhead.

## Basic Configuration

### Minimal Setup

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

This single declaration:
1. Registers `numpy` and `pandas` as available Python libraries
2. Specifies version constraints (used by UV for installation)
3. Enables lazy compilation for both libraries
4. Creates module namespaces `Numpy` and `Pandas`

### Version Specification

Version strings follow Python/pip conventions:

```elixir
libraries: [
  # Semantic versioning
  numpy: "~> 1.26",        # >= 1.26.0, < 2.0.0
  numpy: ">= 1.26, < 2.0", # Explicit range

  # Exact version
  sympy: "== 1.12.0",

  # Latest (not recommended for prod)
  requests: "*",

  # Git repository
  my_lib: {:git, "https://github.com/user/my_lib", tag: "v1.0.0"},

  # Local path (for development)
  local_lib: {:path, "../my_python_lib"}
]
```

## Advanced Configuration

### Per-Library Options

```elixir
libraries: [
  # Simple version
  json: "stdlib",  # Special: uses Python stdlib, no install

  # With options
  numpy: [
    version: "~> 1.26",
    module_name: Np,              # Use `Np.array` instead of `Numpy.array`
    prune: :auto,                 # Enable auto-pruning for this lib
    prune_keep_days: 14,          # Keep unused bindings for 14 days
    cache: :shared,               # Use shared team cache
    extras: ["testing"]           # pip extras to install
  ],

  pandas: [
    version: "~> 2.0",
    module_name: Pd,
    prune: :manual                # Never auto-prune (default)
  ],

  # PyTorch with CUDA
  torch: [
    version: "~> 2.0",
    index_url: "https://download.pytorch.org/whl/cu118",
    extras: ["cuda"]
  ]
]
```

### Stdlib Libraries

Python standard library modules don't need version specs:

```elixir
libraries: [
  json: :stdlib,
  math: :stdlib,
  os: :stdlib,
  pathlib: :stdlib,
  datetime: :stdlib
]
```

These are introspected from the system Python without UV installation.

## Global Configuration

Beyond per-library settings, global options in `config.exs`:

```elixir
# config/config.exs
config :snakebridge,
  # Compilation behavior
  lazy: true,                    # Default: true (v3 behavior)
  parallel_introspection: true,  # Introspect multiple libs concurrently

  # Caching
  cache_dir: "_build/snakebridge",  # Default location
  shared_cache: nil,                 # URL for team cache server (future)

  # Pruning
  auto_prune: false,             # Default: never auto-prune
  prune_keep_days: 30,           # When auto-prune enabled

  # Documentation
  doc_cache_size: 1000,          # Max cached doc entries
  doc_ttl: :infinity,            # How long to cache docs

  # Python environment
  python_executable: nil,        # Auto-detect by default
  uv_executable: nil,            # Auto-detect uv

  # Development
  verbose: false,                # Log generation events
  warn_on_generate: true         # Warn when generating new bindings
```

### Environment-Specific Configuration

```elixir
# config/dev.exs
config :snakebridge,
  verbose: true,
  warn_on_generate: true

# config/prod.exs
config :snakebridge,
  lazy: true,           # Still lazy in prod (cache is pre-built)
  auto_prune: [
    enabled: true,
    keep_days: 7
  ]

# config/test.exs
config :snakebridge,
  # Use mocked Python for tests
  adapter: SnakeBridge.MockAdapter
```

## Module Naming

### Default Names

Library names are converted to CamelCase:

| Python Library | Elixir Module |
|----------------|---------------|
| `numpy` | `Numpy` |
| `pandas` | `Pandas` |
| `scikit-learn` | `ScikitLearn` |
| `my_custom_lib` | `MyCustomLib` |

### Custom Names

Override with `module_name`:

```elixir
libraries: [
  numpy: [version: "~> 1.26", module_name: Np],
  pandas: [version: "~> 2.0", module_name: Pd],
  scikit_learn: [version: "~> 1.3", module_name: Sklearn]
]
```

### Nested Modules

Python submodules become nested Elixir modules:

```
numpy.linalg.solve  →  Numpy.Linalg.solve
scipy.stats.norm    →  Scipy.Stats.norm
```

## Configuration Validation

At compile time, SnakeBridge validates:

1. **Version syntax** — Must be valid pip version specifier
2. **Module names** — Must be valid Elixir module names
3. **Conflicts** — No duplicate library declarations
4. **Stdlib** — Stdlib libs can't have versions

```elixir
# This will fail validation:
libraries: [
  numpy: "~> 1.26",
  numpy: "~> 2.0"        # Error: duplicate library
]

# This will also fail:
libraries: [
  json: "~> 1.0"         # Error: json is stdlib, no version allowed
]
```

## Runtime Configuration

Some settings can be changed at runtime:

```elixir
# Enable verbose logging temporarily
SnakeBridge.configure(verbose: true)

# Check current configuration
SnakeBridge.config()
# => %{lazy: true, cache_dir: "_build/snakebridge", ...}

# Get library info
SnakeBridge.library_info(:numpy)
# => %{version: "1.26.4", module: Numpy, cached_functions: 15}
```

## Configuration Precedence

From highest to lowest priority:

1. Runtime configuration (`SnakeBridge.configure/1`)
2. Environment config (`config/dev.exs`)
3. Base config (`config/config.exs`)
4. Per-library options in `mix.exs`
5. Defaults

## Example: Complete Configuration

```elixir
# mix.exs
defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  defp deps do
    [
      {:snakebridge, "~> 3.0",
       libraries: [
         # Standard library (no install needed)
         json: :stdlib,
         math: :stdlib,

         # Data science stack
         numpy: [version: "~> 1.26", module_name: Np],
         pandas: [version: "~> 2.0", module_name: Pd],
         scipy: "~> 1.11",

         # ML
         scikit_learn: [version: "~> 1.3", module_name: Sklearn],
         torch: [
           version: "~> 2.0",
           index_url: "https://download.pytorch.org/whl/cu118"
         ],

         # Symbolic math
         sympy: [
           version: "~> 1.12",
           prune: :auto,
           prune_keep_days: 7
         ]
       ]},

      # Other deps...
    ]
  end
end
```

```elixir
# config/config.exs
import Config

config :snakebridge,
  cache_dir: "_build/snakebridge",
  doc_cache_size: 500

import_config "#{config_env()}.exs"
```

```elixir
# config/dev.exs
import Config

config :snakebridge,
  verbose: true,
  warn_on_generate: true
```

```elixir
# config/prod.exs
import Config

config :snakebridge,
  verbose: false,
  auto_prune: [enabled: true, keep_days: 7]
```

## Migration from v2

v2 configuration:
```elixir
# config/config.exs (v2)
config :snakebridge,
  adapters: [:json, :math, :sympy]
```

v3 equivalent:
```elixir
# mix.exs (v3)
{:snakebridge, "~> 3.0",
 libraries: [
   json: :stdlib,
   math: :stdlib,
   sympy: "~> 1.12"
 ]}
```

The migration tool handles this automatically:
```bash
mix snakebridge.migrate
```
