# Vision: The Lazy, Elastic Python Ecosystem for Elixir (2025-12-25)

**Goal**: Build the most frictionless and scalable way for Elixir developers and AI systems to use Python libraries without surrendering the benefits of compile-time tooling.

## The Core Shift

The previous architecture attempted to mirror entire Python libraries into Elixir adapters and full documentation. That is a powerful idea, but it breaks down at scale. SymPy alone can generate thousands of modules and tens of thousands of docs. Generating everything up front is the wrong default.

The new vision is an **elastic bridge**:

- It starts light and precise, only building what you actually use.
- It grows as your usage grows, and never shrinks unless you ask.
- It keeps tooling benefits by generating real `.ex` source files.

## Why This Matters (Product View)

AI and ML teams need three things at once:

1. **Fast iteration**: they do not want long compile times or large diffs.
2. **Repeatable builds**: they need deterministic outcomes and versioned adapters.
3. **Exploration at speed**: they need instant access to docs and discovery.

The lazy architecture hits all three:

- Minimal initial generation keeps iteration fast.
- Cached generation and pinned versions keep builds stable.
- On-demand docs keep exploration fast without building everything.

## The Innovation Signals

This ecosystem should look obviously innovative to outside observers because it treats bridging as a **dynamic product**, not just a codegen tool.

- **Elastic API surface**: The adapter grows based on usage signals.
- **Docs as a query system**: Document rendering is a cache-backed service.
- **Agent-ready by default**: programmatic access to symbol search and docs is a first-class API.
- **Hermetic but lightweight**: Python env bootstrapping is automated and safe, but invisible to users.

## The UX Story

The best UX is a 2-line change:

```
{:snakepit, "~> 0.4.0",
 snakebridge: [libraries: [sympy: "1.12", numpy: "1.26"], docs: :on_demand]}
```

From there, everything feels automatic:

- `mix compile` detects used symbols and generates adapters.
- `Sympy.__functions__/0` and `Sympy.__search__/1` let you explore.
- `mix snakepit.docs sympy.integrate` gives a full HTML page on demand.

## What We Refuse To Do

- We do not generate an entire library just to produce docs.
- We do not require users to create Python venvs or run pip manually.
- We do not delete adapters unless explicitly asked.

## The Resulting Ecosystem

Snakepit becomes the runtime substrate. Snakebridge becomes the introspection and codegen layer. Together they provide:

- Deterministic, cached adapter generation
- On-demand docs that scale to giant libraries
- A strong UX loop for exploration and growth

This is the architecture we should ship and defend.

