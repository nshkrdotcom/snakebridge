# Interactive Development Experience

## Core Principle

AutoBridge transforms library integration from "configure then use" to "use and refine together". The AI observes your patterns and proposes improvements inline.

---

## IEx Integration

### Installation

```elixir
# In .iex.exs or manually:
iex> AutoBridge.DevShell.install()
AutoBridge DevShell activated 🐍🌉
```

### Discovery

```elixir
iex> use AutoBridge, :sympy

╭─────────────────────────────────────────────────────────────╮
│ 🔍 Discovering sympy...                                     │
│ Found: 847 functions, 124 classes                          │
│ ✓ AutoBridge.SymPy ready (learning mode)                   │
╰─────────────────────────────────────────────────────────────╯
```

---

## Refinement Proposals

As you use functions, AI proposes improvements:

```elixir
iex> AutoBridge.SymPy.expand("(x + 1)**3")
{:ok, "x**3 + 3*x**2 + 3*x + 1"}

╭─────────────────────────────────────────────────────────────╮
│ 🧠 Refinement Proposal                                      │
├─────────────────────────────────────────────────────────────┤
│ Function: expand/1                                          │
│ Proposed: @spec expand(String.t()) :: {:ok, String.t()}    │
│ Confidence: 94%                                             │
│ [a]ccept  [r]eject  [m]odify  [s]kip                       │
╰─────────────────────────────────────────────────────────────╯

iex> a
✓ Refinement applied
```

### Commands

| Key | Action |
|-----|--------|
| `a` | Accept proposal |
| `r` | Reject permanently |
| `m` | Modify with custom value |
| `s` | Skip for now |
| `d` | Show details |

---

## Status Dashboard

```elixir
iex> AutoBridge.status(:sympy)
%{
  phase: :learning,
  confidence: 73,
  observations: 124,
  pending_refinements: 3,
  functions_used: "23/847"
}
```

### Pending Refinements

```elixir
iex> AutoBridge.pending(:sympy)
[
  %{id: 1, type: :typespec, target: "solve/2", confidence: 94},
  %{id: 2, type: :default, target: "simplify/2", confidence: 87}
]

iex> AutoBridge.accept(1)
✓ Typespec for solve/2 applied
```

---

## Batch Operations

```elixir
# Accept all high-confidence proposals
iex> AutoBridge.accept_all(:sympy, min_confidence: 0.9)
Accepted 2 refinements

# Enable auto-accept for rapid prototyping
iex> AutoBridge.configure(:sympy, auto_accept: true, threshold: 0.95)
```

---

## Error Learning

AutoBridge learns from errors too:

```elixir
iex> AutoBridge.SymPy.solve(123, :x)
{:error, :type_error}

# May propose validation guard:
│ Proposed: Add `when is_binary(expr)` guard │
```

---

## Finalization

When confidence reaches threshold:

```elixir
╭─────────────────────────────────────────────────────────────╮
│ 🎯 sympy ready for finalization (97% confidence)           │
│ Run `AutoBridge.finalize(:sympy)` when ready               │
╰─────────────────────────────────────────────────────────────╯

iex> AutoBridge.finalize(:sympy)
Step 1/5: Validating... ✓
Step 2/5: Generating tests... ✓
Step 3/5: Running tests... ✓
Step 4/5: Compiling... ✓
Step 5/5: Documenting... ✓

✓ sympy frozen and production-ready!
```

---

## Notification Control

```elixir
# Silence notifications
iex> AutoBridge.DevShell.quiet()

# Enable all notifications
iex> AutoBridge.DevShell.verbose()

# Configure via config.exs
config :autobridge, notification_level: :normal  # :quiet | :normal | :verbose | :silent
```

---

## Troubleshooting

```elixir
# Confidence stuck?
iex> AutoBridge.diagnose(:sympy)
# Shows what's limiting confidence

# Accidentally rejected?
iex> AutoBridge.undo(:sympy)

# Focus on subset of functions
iex> AutoBridge.focus(:sympy, only: [:solve, :simplify, :expand])
```
