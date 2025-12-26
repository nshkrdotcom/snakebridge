# ML Pillars (SnakeBridge Responsibilities)

SnakeBridge is compile-time only. The ML-grade runtime features (zero-copy,
crash barrier, hermetic Python, exception translation) are **owned by Snakepit
Prime runtime**. This document defines what SnakeBridge must do to stay
compatible with those runtime pillars.

## 1) Zero-Copy Interop Compatibility

Snakepit Prime exposes zero-copy handles (`Snakepit.ZeroCopyRef`). SnakeBridge
must:

- Preserve `Snakepit.ZeroCopyRef` values as-is in payloads
- Avoid any serialization/transformation of those handles
- Document zero-copy support in generated moduledocs

## 2) Crash Barrier Compatibility

Snakepit Prime uses the `idempotent` flag to decide whether a call can be safely
retried after a worker crash. SnakeBridge must:

- Allow per-function `idempotent` metadata (config or annotations)
- Emit `idempotent` in payloads for all calls
- Document default behavior (false unless explicitly marked)

## 3) Exception Translation Compatibility

Snakepit Prime returns structured error structs. SnakeBridge must:

- Reference `Snakepit.Error.t()` (and subtypes) in generated specs
- Avoid wrapping or reformatting runtime errors
- Preserve error metadata in docs and examples

## 4) Hermetic Runtime Identity

Snakepit Prime can run with a managed Python interpreter. SnakeBridge must:

- Record runtime identity (Python version, platform, runtime hash) in
  `snakebridge.lock`
- Treat runtime identity drift as invalidation for regeneration

## Summary

SnakeBridge does not implement ML runtime features. It ensures generated wrappers
emit payloads and types that let Snakepit Prime deliver those guarantees.

For runtime details, see the Snakepit Prime runtime docs.
