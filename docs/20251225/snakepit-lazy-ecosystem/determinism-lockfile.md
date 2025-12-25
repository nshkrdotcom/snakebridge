# Determinism and Lockfile Strategy

This document addresses determinism, merge conflicts, and CI cold starts.

## Why a Lockfile Exists

Adapter generation depends on the Python environment and generator version. Without a lockfile, two machines can generate different wrappers from the same Elixir code.

`snakebridge.lock` captures the **environment identity** needed to make generation reproducible.

## Environment Identity

The lockfile records:

- Snakepit/Snakebridge version
- Generator hash
- Python version
- Platform tag (os, arch)
- Resolved Python dependency set
- Registry metadata version or checksum

If any part changes, adapters are considered invalid until regenerated.

## Lockfile Format (Example)

```
%{
  toolchain: %{
    snakepit: "0.4.0",
    snakebridge: "0.4.0",
    generator_hash: "sha256:..."
  },
  python: %{version: "3.11.7", platform: "linux-x86_64"},
  libraries: %{
    sympy: %{requested: "1.12", resolved: "1.12.0", hash: "sha256:..."},
    numpy: %{requested: "1.26", resolved: "1.26.4", hash: "sha256:..."}
  },
  metadata: %{source: :hex, version: "2025.12.25", hash: "sha256:..."}
}
```

Entries are written in a stable, sorted order to minimize diffs.

## Merge Conflicts (The Real Fix)

The lockfile is the only file that can conflict. We address this in three ways:

1. **Deterministic ordering**: entries are sorted by library name.
2. **Stable formatting**: no timestamps in the lockfile body.
3. **Regeneratable**: `mix snakepit.lock --rebuild` can rebuild from metadata.

If a conflict occurs, resolve by regenerating the lockfile and re-running `mix compile`.

## Generated Source: Commit or Cache?

The default policy is **commit generated adapters** under `lib/snakebridge_generated/`.

Why:

- CI does not need Python for compilation.
- Releases are "pure Elixir" once adapters exist.
- Diffs represent real API usage.

Teams that prefer not to commit adapters can set `strict: false` in CI and rely on Python at build time, but this is not the recommended posture.

## Manifest Strategy

We avoid a single monolithic manifest to reduce merge conflicts:

- Per-library metadata lives under `lib/snakebridge_generated/<lib>/_meta.json`.
- A global manifest can be rebuilt from generated files.
- The lockfile remains the only authoritative source of environment identity.

## CI Cold Start

Recommended CI steps:

1. Restore `lib/snakebridge_generated/` and `snakebridge.lock` from git.
2. Run `mix compile` in `strict: true` mode.
3. Fail fast if generation would be required.

This ensures deterministic builds without requiring Python in CI.

