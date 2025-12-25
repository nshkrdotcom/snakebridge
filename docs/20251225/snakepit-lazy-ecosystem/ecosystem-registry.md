# Ecosystem and Registry Strategy

A scalable bridge needs a registry of library metadata so developers do not have to re-introspect from scratch.

## Registry Goals

- Fast metadata retrieval without running Python
- Versioned, reproducible metadata
- Community-owned but curated

## Proposed Registry Model

### Package Namespace

- `snakepit_libs_sympy` (metadata for SymPy)
- `snakepit_libs_numpy` (metadata for NumPy)

Each package contains:

- `metadata.json` (symbols, docstrings, signatures)
- `types.json` (type hints and mapping)
- `docs_index.json` (summary search data)

### Resolution Priority

1. Local cache (if version matches)
2. Registry package (if available)
3. Local introspection (last resort)

## Publishing Flow

- `mix snakepit.pack sympy` generates metadata package
- The package is published to Hex under `snakepit_libs_*`
- Consumers resolve it automatically on compile

## Why This Matters

The registry allows:

- Fast setup for common libraries
- Deterministic builds in CI
- Minimal Python execution in build pipelines

## Governance

- Curated core libraries (SymPy, NumPy, Pandas, Torch, etc)
- Community packages with trust metadata
- Optional signed metadata for enterprise use

