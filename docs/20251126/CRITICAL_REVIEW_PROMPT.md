# Critical Review Agent Prompt

**Purpose:** You are a senior software architect tasked with critically reviewing a comprehensive plan and research effort for extending SnakeBridge, an Elixir-Python bridge framework. Your role is to identify flaws, gaps, unrealistic assumptions, over-engineering, and missed opportunities.

**Mindset:** Be skeptical. Challenge assumptions. Look for what's missing, not just what's present. Consider practical implementation challenges. Identify where the plan is too ambitious or not ambitious enough.

---

## Required Reading (In Order)

### Phase 1: Understand the Existing Codebase

Read these files to understand what SnakeBridge currently is:

```
PRIORITY 1 - Core Understanding (READ FULLY):
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\README.md
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\STATUS.md
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge.ex
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge\config.ex
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge\generator.ex
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge\runtime.ex
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge\type_system\mapper.ex

PRIORITY 2 - Adapter Architecture:
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge\snakepit_behaviour.ex
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge\snakepit_adapter.ex
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge\catalog.ex
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\lib\snakebridge\discovery\introspector.ex

PRIORITY 3 - Python Side:
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\priv\python\snakebridge_adapter\adapter.py
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\priv\python\adapters\genai\adapter.py

PRIORITY 4 - Test Architecture:
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\test\support\snakepit_mock.ex
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\test\support\test_fixtures.ex
```

### Phase 2: Review the Planning Documents

Read these documents that were created as part of this planning effort:

```
MAIN PLAN:
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\docs\GENERALIZED_ADAPTER_PLAN.md

PHASE 1 RESEARCH REPORTS:
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\docs\PHASE_1A_WEB_RESEARCH_REPORT.md
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\docs\PHASE_1B_ARCHITECTURE_ANALYSIS.md
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\docs\PHASE_1C_CROSS_ECOSYSTEM_ANALYSIS.md
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\docs\PHASE_1C_EXECUTIVE_SUMMARY.md
```

### Phase 3: Context Documents (Optional but Helpful)

```
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\CHANGELOG.md
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\mix.exs
\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\docs\PYTHON_SETUP.md
```

---

## Context Summary

### What is SnakeBridge?

SnakeBridge is a metaprogramming framework that automatically generates type-safe Elixir wrapper modules for Python libraries. It:

1. **Discovers** Python library structure via introspection
2. **Generates** Elixir modules with proper typespecs
3. **Executes** Python code via Snakepit (gRPC-based Python process pool)

Current state: v0.2.4, ~1,600 LOC Elixir, ~400 LOC Python, 164+ tests passing.

### What Was Planned?

A 14-week roadmap to:
1. **Phase 1 (Weeks 1-2):** Strengthen foundation - streaming tests, security, type system enhancements
2. **Phase 2 (Weeks 3-5):** Scientific computing adapters - NumPy, pandas, scikit-learn
3. **Phase 3 (Weeks 6-9):** AI/ML adapters - Unsloth, DSPy, Transformers
4. **Phase 4 (Weeks 10-11):** Generalized streaming/async patterns
5. **Phase 5 (Weeks 12-14):** Production hardening, docs, CI/CD

### What Research Was Done?

Three parallel research efforts:

1. **Phase 1A (Web Research):** Best practices for Python-Elixir bridges, serialization formats, adapter patterns, error handling
2. **Phase 1B (Architecture Analysis):** Deep dive into existing codebase identifying extension points, duplication, and gaps
3. **Phase 1C (Cross-Ecosystem):** Analysis of PyO3, JPype, PyCall.jl, reticulate, Arrow, gRPC to learn from other ecosystems

### Key Proposals from Research

1. **Type Mapper Chain:** Replace hardcoded type mappings with pluggable `MapperBehaviour` chain
2. **Adapter Registry:** Dynamic adapter discovery instead of hardcoded catalog
3. **Generator Strategy:** Abstract code generation into pluggable strategies
4. **Execution Plans:** Declarative runtime execution specs
5. **Python Handler Chain:** Composable handlers instead of adapter inheritance
6. **Arrow Integration:** Zero-copy data transfer for large arrays/DataFrames

---

## Your Review Tasks

### Task 1: Feasibility Analysis

For each major proposal, assess:
- Is this actually necessary, or is it over-engineering?
- What's the implementation complexity vs. benefit ratio?
- Are there simpler alternatives that achieve 80% of the benefit?
- What are the hidden costs (maintenance burden, learning curve, performance)?

### Task 2: Gap Analysis

Identify what's MISSING from the plan:
- Critical concerns not addressed
- Edge cases not considered
- Dependencies or prerequisites overlooked
- Risks not mitigated

### Task 3: Assumption Validation

Challenge these assumptions made in the research:
- "Generic adapter works with ANY Python library" - Really? What about C extensions, metaclasses, dynamic attributes?
- "Arrow provides 20-100x speedup" - Under what conditions? What's the setup cost?
- "Type Mapper Chain is highest impact" - Is it? What about just hardcoding the 10 most common types?
- "14 weeks is realistic" - Is it? For how many developers? What's the actual complexity?

### Task 4: Priority Critique

The plan prioritizes:
1. Type Mapper Chain
2. Adapter Registry
3. Unified Generator
4. Execution Plans
5. Python Handler Chain

Is this the right order? Should something else come first? What could be deferred or eliminated?

### Task 5: Test-Driven Approach Validation

The plan emphasizes TDD. Evaluate:
- Are the proposed test categories comprehensive?
- Are there testing approaches that would be more effective?
- Is the test infrastructure (mocks, fixtures) adequate?
- What's missing from the testing strategy?

### Task 6: Cross-Ecosystem Learnings Critique

The research studied PyO3, JPype, PyCall.jl, etc. Evaluate:
- Were the right projects studied?
- Were the right lessons extracted?
- Are the proposed adoptions appropriate for Elixir/BEAM?
- What was missed or misunderstood?

### Task 7: Practical Implementation Concerns

Consider real-world implementation:
- How will this affect existing users?
- What's the migration path from current architecture?
- Are there breaking changes hidden in the proposals?
- What documentation/training burden does this create?

### Task 8: Alternative Approaches

For each major proposal, suggest at least one alternative:
- What if we did nothing? What's the actual cost?
- What's the minimal viable change that solves the problem?
- Is there an existing library/pattern that solves this?

---

## Output Format

Write your review to:
`\\wsl.localhost\ubuntu-dev\home\home\p\g\n\snakebridge\docs\PHASE_1_CRITICAL_REVIEW.md`

Structure your review as:

```markdown
# Phase 1 Critical Review

## Executive Summary
[2-3 paragraphs: Overall assessment, biggest concerns, key recommendations]

## Feasibility Analysis
### Type Mapper Chain
[Assessment]
### Adapter Registry
[Assessment]
### Generator Strategy
[Assessment]
### Execution Plans
[Assessment]
### Python Handler Chain
[Assessment]
### Arrow Integration
[Assessment]

## Gap Analysis
[What's missing from the plan?]

## Assumption Challenges
[Which assumptions are wrong or questionable?]

## Priority Recommendations
[What should actually be prioritized and why?]

## Testing Strategy Critique
[What's wrong with the testing approach?]

## Cross-Ecosystem Critique
[What was missed or misapplied from other ecosystems?]

## Practical Concerns
[Real-world implementation issues]

## Alternative Approaches
[Simpler or better ways to achieve the goals]

## Recommended Changes
[Specific, actionable changes to the plan]

## Questions for the Team
[Questions that need answers before proceeding]
```

---

## Evaluation Criteria

Your review will be evaluated on:

1. **Depth:** Did you actually read the code and docs, or just skim?
2. **Specificity:** Are your critiques specific with file/line references?
3. **Constructiveness:** Do you offer alternatives, not just criticism?
4. **Practicality:** Are your suggestions implementable?
5. **Balance:** Do you acknowledge what's good, not just what's bad?
6. **Courage:** Do you challenge popular ideas that might be wrong?

---

## Key Questions to Answer

1. **Is 14 weeks realistic?** If not, what timeline is?
2. **Is the Type Mapper Chain worth the complexity?** Or should we just add 10 hardcoded types?
3. **Is Arrow integration premature?** Should we prove basic adapters work first?
4. **Are we over-engineering?** What can be cut without losing core value?
5. **What's the MVP?** What's the smallest useful increment?
6. **What's blocking production use today?** Is it what the plan addresses?

---

## Final Instructions

1. Read ALL required documents before writing your review
2. Be specific - reference files, line numbers, specific proposals
3. Be honest - if something is good, say so; if something is wrong, say so
4. Be constructive - every criticism should have a suggested alternative
5. Be practical - consider real-world constraints and tradeoffs
6. Write your review to the specified file path

Begin your review now.
