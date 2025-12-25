# UX Journeys: Developer-First Flows

This document describes the expected developer experience across the most common tasks.

## Journey 1: Fresh Project

1. Add dependency and libraries to `mix.exs`.
2. Run `mix deps.get`.
3. `mix compile` runs a prepass, generates adapters, and updates `snakebridge.lock`.
4. Use `Library.__functions__/0` to explore.
5. Call functions with normal Elixir syntax.

Expected feelings:

- "I did not need to touch Python."
- "It just works with a few lines of config."

## Journey 2: Exploration and Discovery

1. Run `Snakepit.search("sympy", "matrix")` in IEx.
2. Use `Snakepit.doc("sympy.Matrix")` to see class docs.
3. Generate adapters on demand if not already present.

Expected feelings:

- "I can explore without reading giant docs."
- "I can jump from search to docs in seconds."

## Journey 3: Incremental Growth

1. Add new calls in code (`Sympy.integrate/2`).
2. Compile. Adapters are extended and the lockfile stays deterministic.
3. Previously generated wrappers remain unchanged.

Expected feelings:

- "No huge diffs."
- "The adapter grows with me."

## Journey 4: Cleanup

1. Run `mix snakepit.prune` when a cleanup is desired.
2. Review the diff.
3. Commit a smaller adapter surface.

Expected feelings:

- "Pruning is my choice."
- "I trust the system not to surprise me."

## Journey 5: Agent-Assisted Workflow

1. Agent searches for symbols.
2. Agent requests docs and signatures.
3. Agent ensures adapters or uses explicit `Snakepit.dynamic_call/4`.

Expected feelings:

- "The agent can use the same safe surface as I do."
