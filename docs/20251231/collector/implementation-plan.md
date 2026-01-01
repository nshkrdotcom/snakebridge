# IMPLEMENTATION PLAN: SnakeBridge v0.8.7 MVP Critical Fixes

**Generated:** 2025-12-31
**Source Documents:** 5 research files in `docs/20251231/`
**Target Version:** v0.8.7

---

## SUMMARY TABLE OF ALL ISSUES

| ID | Issue | Research Doc | Severity | Files Affected |
|----|-------|--------------|----------|----------------|
| SC-1 | Session ID inconsistency across call paths | session-consistency | Critical | `lib/snakebridge/runtime.ex` |
| SC-2 | `__runtime__` session override ignored for atom modules | session-consistency | Critical | `lib/snakebridge/runtime.ex` |
| RL-1 | No first-class ref errors (RefNotFoundError, etc.) | ref-lifecycle | High | `lib/snakebridge/error_translator.ex`, Python adapter |
| RL-2 | TTL documentation contradictions | ref-lifecycle | Medium | `lib/snakebridge.ex`, `lib/snakebridge/session_context.ex`, `README.md` |
| IF-1 | Introspection errors silently swallowed | introspection-failures | Critical | `lib/mix/tasks/compile/snakebridge.ex` |
| IF-2 | No user visibility into introspection failures | introspection-failures | High | `lib/mix/tasks/compile/snakebridge.ex` |
| DD-1 | `set_attr` return type mismatch in docs | doc-defaults | Medium | `lib/snakebridge.ex` |
| DD-2 | Missing `release_ref`/`release_session` delegates | doc-defaults | Medium | `lib/snakebridge.ex` |
| DD-3 | SessionContext TTL doc says 30min, default is 1hr | doc-defaults | Low | `lib/snakebridge/session_context.ex` |
| RA-1 | Pre-populated registry.json files in git | registry-artifacts | High | `.gitignore`, 9 registry.json files |

---

## DEPENDENCY GRAPH

```
                    RA-1 (Registry Cleanup)
                         |
                         v
         +---------------+---------------+
         |               |               |
         v               v               v
    SC-1/SC-2       RL-1/RL-2       IF-1/IF-2
  (Session Fix)   (Ref Errors)   (Introspection)
         |               |               |
         +-------+-------+               |
                 |                       |
                 v                       |
            DD-1/DD-2/DD-3 <-------------+
           (Doc/API Fixes)
```

**Dependency Analysis:**

1. **RA-1 (Registry Cleanup)** - INDEPENDENT: No code dependencies, pure git/file cleanup
2. **SC-1/SC-2 (Session Consistency)** - INDEPENDENT: Modifies runtime.ex session resolution
3. **RL-1/RL-2 (Ref Lifecycle)** - INDEPENDENT: Creates new error types, updates translator
4. **IF-1/IF-2 (Introspection)** - INDEPENDENT: Modifies compile task only
5. **DD-1/DD-2/DD-3 (Doc/API)** - DEPENDS ON SC, RL: Should run LAST

---

## PROPOSED PROMPT BREAKDOWN: 4 PROMPTS

### PROMPT 1: Registry Cleanup and Gitignore (Standalone)

**Goal:** Remove pre-populated registry artifacts and prevent future tracking

**Tasks:**
1. Delete `/priv/snakebridge/registry.json`
2. Delete all 8 `examples/*/priv/snakebridge/registry.json` files
3. Add `priv/snakebridge/registry.json` to `.gitignore`
4. Update CHANGELOG.md with removal note

**Files to Modify:**
- `.gitignore` (add patterns)
- `CHANGELOG.md` (add entry)

**Files to Delete:**
- `priv/snakebridge/registry.json`
- All 8 example project registry.json files

---

### PROMPT 2: Session ID Consistency Fix (Core Runtime)

**Goal:** Ensure all call paths respect `__runtime__: [session_id: X]` override

**Tasks:**
1. Write tests for session ID consistency across all call paths
2. Fix `call/4` (atom modules) to use `resolve_session_id(runtime_opts)`
3. Fix `get_module_attr/3` (both variants) to use `resolve_session_id()`
4. Fix `call_class/4` to use `resolve_session_id()`
5. Fix `call_helper/3` (both variants) to use `resolve_session_id()`
6. Fix `stream/5` (atom) to use `resolve_session_id()`
7. Update CHANGELOG.md

**Files to Modify:**
- `lib/snakebridge/runtime.ex` (main fixes)
- `test/snakebridge/session_consistency_test.exs` (new tests)
- `CHANGELOG.md`

---

### PROMPT 3: Ref Lifecycle Errors + Introspection Visibility

**Goal:** Create first-class ref errors and make introspection failures visible

**Part A: Ref Lifecycle Errors**
1. Create new error modules: RefNotFoundError, SessionMismatchError, InvalidRefError
2. Update `lib/snakebridge/error_translator.ex` to translate ref errors
3. Update Python adapter error messages for parseability

**Part B: Introspection Visibility**
4. Modify `update_manifest/2` to log errors with `Mix.shell().info/1`
5. Emit telemetry events for introspection failures
6. Add summary output after normal mode compile

**Files to Modify:**
- `lib/snakebridge/ref_not_found_error.ex` (new)
- `lib/snakebridge/session_mismatch_error.ex` (new)
- `lib/snakebridge/invalid_ref_error.ex` (new)
- `lib/snakebridge/error_translator.ex`
- `priv/python/snakebridge_adapter.py`
- `lib/mix/tasks/compile/snakebridge.ex`
- `CHANGELOG.md`

---

### PROMPT 4: Documentation and API Alignment (Final Polish)

**Goal:** Fix all doc/implementation mismatches and add missing delegates

**Tasks:**
1. Fix `set_attr` documentation in `lib/snakebridge.ex`
2. Add `release_ref` and `release_session` delegates to `lib/snakebridge.ex`
3. Fix TTL documentation inconsistencies across all files
4. Write tests for new delegates
5. Update CHANGELOG.md

**Files to Modify:**
- `lib/snakebridge.ex` (specs, delegates, docs)
- `lib/snakebridge/session_context.ex` (TTL docs)
- `README.md` (if needed)
- `test/snakebridge/api_delegates_test.exs` (new)
- `CHANGELOG.md`

---

## PROMPT INDEPENDENCE ANALYSIS

| Prompt | Can Run Independently | Dependencies |
|--------|----------------------|--------------|
| 1 (Registry) | YES | None |
| 2 (Session) | YES | None |
| 3 (Errors) | YES | None |
| 4 (Docs) | NO | Depends on 2, 3 for final API/behavior |

**Recommended Execution Order:**
1. Prompt 1 (quick win, cleans git status)
2. Prompts 2 and 3 (can run in parallel if resources allow)
3. Prompt 4 (final polish after core fixes complete)

---

## SUCCESS CRITERIA

Each prompt should end with:
1. All new tests passing
2. All existing tests passing
3. `mix dialyzer` clean
4. `mix credo --strict` clean
5. CHANGELOG.md updated for v0.8.7
6. Git commit with descriptive message

---

## CRITICAL FILES FOR IMPLEMENTATION

| File | Prompts | Role |
|------|---------|------|
| `lib/snakebridge/runtime.ex` | 2 | Session consistency fixes (lines 56-70, 440-489) |
| `lib/mix/tasks/compile/snakebridge.ex` | 3 | Introspection visibility (lines 65-82) |
| `lib/snakebridge.ex` | 4 | API delegates and docs (lines 48, 367-369) |
| `lib/snakebridge/error_translator.ex` | 3 | Ref error translation |
| `priv/python/snakebridge_adapter.py` | 3 | Error message formatting (lines 617, 189) |
| `.gitignore` | 1 | Registry pattern |
| `CHANGELOG.md` | ALL | Version history |
