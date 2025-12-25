# Agentic Workflows: Programmatic Discovery and Use

The lazy bridge should be usable by automation and AI agents without extra glue. This document describes how agents can use discovery and docs to plan and execute Python calls safely.

## The Problem

Agents need to explore APIs, understand types, and call functions with minimal overhead. A full adapter generation pass is too slow for iterative agent loops.

## The Solution

Expose a small, structured interface that lets agents:

- list available symbols
- search by keyword
- fetch structured docs and signatures
- request on-demand adapter generation

## Proposed APIs

### Discovery

```
Snakepit.list_libraries()
Snakepit.list_symbols("sympy")
Snakepit.search("sympy", "integrate")
```

### Doc and Signature Fetch

```
Snakepit.doc("sympy.integrate")
Snakepit.signature("sympy.integrate")
```

### On-Demand Adapter Generation

```
Snakepit.ensure_adapter("sympy.integrate")
```

This call checks the generated source set and triggers a deterministic prepass if missing. In `strict: true`, it fails with guidance instead of generating.

## Safety and Guardrails

- Enforce library allowlists from `mix.exs` configuration
- Rate limit dynamic calls
- Provide structured error messages for missing symbols
- Keep ledger promotion explicit so agent behavior is reproducible

## Example Agent Loop

1. Agent searches for relevant symbols.
2. Agent requests docs and signature for a candidate function.
3. Agent ensures adapter generation.
4. Agent calls the function using the generated wrapper.

This is a clean, deterministic loop that fits well into long-running agentic tasks.
