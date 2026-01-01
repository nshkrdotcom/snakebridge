# INTROSPECTION FAILURE BEHAVIOR RESEARCH: MVP-CRITICAL ISSUE #3

**Investigation Date:** December 31, 2025
**Scope:** How SnakeBridge handles introspection failures in normal vs strict mode
**Status:** Silent failure pattern identified

## EXECUTIVE SUMMARY

SnakeBridge's compile task **silently swallows introspection errors** in normal mode (line 78-79 in snakebridge.ex), allowing compilation to proceed with an incomplete manifest. This creates a dangerous user experience:

1. The generator runs successfully
2. The manifest becomes incomplete (missing symbols that failed to introspect)
3. Compilation later fails in user code with "undefined function" errors
4. Users have no visibility into what went wrong during introspection

---

## ARCHITECTURE OVERVIEW

The compile task follows this flow:

```
run_with_config(config)
  ├── strict_mode?(config)
  │   └── run_strict(config)        [RAISES on errors]
  │       ├── scan_project()        [Find used functions]
  │       ├── manifest.load()       [Load cached symbols]
  │       ├── missing = manifest.missing()
  │       └── RAISES if missing != []
  │
  └── run_normal(config)           [CONTINUES despite errors]
      ├── scan_project()
      ├── manifest.load()
      ├── missing = manifest.missing()
      ├── targets = build_targets()
      ├── update_manifest()         [ERROR SWALLOWED HERE]
      ├── manifest.save()
      ├── generate_from_manifest()
      └── {:ok, []}
```

---

## CRITICAL ISSUE #1: INTROSPECTION ERROR SWALLOWING

**Location:** `lib/mix/tasks/compile/snakebridge.ex:65-82`

```elixir
defp update_manifest(manifest, targets) do
  targets
  |> Introspector.introspect_batch()
  |> Enum.reduce(manifest, fn {library, result, python_module}, acc ->
    case result do
      {:ok, infos} ->
        {symbol_entries, class_entries} =
          build_manifest_entries(library, python_module, infos)

        acc
        |> Manifest.put_symbols(symbol_entries)
        |> Manifest.put_classes(class_entries)

      {:error, _reason} ->
        acc                           # <-- ERROR SWALLOWED HERE
    end
  end)
end
```

**The Problem:**
- Line 78-79 pattern matches `{:error, _reason} -> acc`
- The error is completely ignored
- The accumulator (manifest) is returned unchanged
- No logging, no telemetry, no user notification

**What gets lost:**
- The introspection error details
- Knowledge that certain symbols failed to introspect
- Any opportunity to alert the user

---

## CRITICAL ISSUE #2: BATCH INTROSPECTION ERROR HANDLING

**Location:** `lib/snakebridge/introspector.ex:78-106`

The introspection batch returns tuples with three elements:

```elixir
def introspect_batch(libs_and_functions) when is_list(libs_and_functions) do
  libs_and_functions
  |> Enum.zip(results)
  |> Enum.map(fn
    {{_library, _python_module, _functions}, {:ok, result}} ->
      result
    {{library, python_module, functions}, {:exit, reason}} ->
      {library, {:error, batch_error(library, python_module, functions, reason)}, python_module}
    {{library, python_module, functions}, {:error, reason}} ->
      {library, {:error, batch_error(library, python_module, functions, reason)}, python_module}
  end)
end
```

Each batch error is a map containing:
- `type: :introspection_batch_failed`
- `library:` the library label
- `python_module:` the module being introspected
- `functions:` list of function names that failed
- `reason:` underlying error reason

---

## POSSIBLE INTROSPECTION ERRORS

**Defined in IntrospectionError module** (`lib/snakebridge/introspection_error.ex`):

### 1. Package Not Found (`:package_not_found`)
- Pattern: "ModuleNotFoundError"
- Regex: `ModuleNotFoundError: No module named '([^']+)'`
- Suggestion: "Run: mix snakebridge.setup"
- User Experience: Library not installed in Python environment

### 2. Import Error (`:import_error`)
- Pattern: "ImportError"
- Example: "ImportError: cannot import name 'cuda' from 'torch'"
- Suggestion: "Check library dependencies or install optional extras"
- User Experience: Optional features not available

### 3. Timeout Error (`:timeout`)
- Pattern: "TimeoutError" or "timed out"
- Regex: `TimeoutError: (.+)`
- Suggestion: "Increase introspection timeout or retry"
- User Experience: Introspection too slow (default 30s)

### 4. Introspection Bug (`:introspection_bug`)
- Pattern: Any other Python error
- Extracts last line with "Error" in output
- Suggestion: "Please report this issue with the Python error output"
- User Experience: Unexpected failure during introspection

---

## STRICT MODE VS NORMAL MODE

### Strict Mode (`lib/mix/tasks/compile/snakebridge.ex:405-433`)

```elixir
defp run_strict(config) do
  manifest = Manifest.load(config)
  detected = scanner_module().scan_project(config)
  missing = Manifest.missing(manifest, detected)

  if missing != [] do
    formatted = format_missing(missing)

    raise SnakeBridge.CompileError, """
    Strict mode: #{length(missing)} symbol(s) not in manifest.
    """
  end

  verify_generated_files_exist!(config)
  verify_symbols_present!(config, manifest)

  {:ok, []}
end
```

**Key Differences:**
1. Strict mode LOADS manifest but does NOT introspect
2. Strict mode ONLY verifies that cached symbols exist in generated files
3. Strict mode expects all symbols to be pre-computed (CI scenario)
4. Strict mode RAISES on any missing symbols
5. Normal mode ATTEMPTS to fill gaps by introspecting

---

## NORMAL MODE FLOW IN DETAIL

**Location:** `lib/mix/tasks/compile/snakebridge.ex:435-468`

```elixir
defp run_normal(config) do
  start_time = System.monotonic_time()
  libraries = Enum.map(config.libraries, & &1.name)
  Telemetry.compile_start(libraries, false)

  try do
    detected = scanner_module().scan_project(config)
    manifest = Manifest.load(config)
    missing = Manifest.missing(manifest, detected)
    targets = build_targets(missing, config, manifest)

    updated_manifest =
      if targets != [] do
        update_manifest(manifest, targets)    # <-- ERRORS SWALLOWED HERE
      else
        manifest
      end

    Manifest.save(config, updated_manifest)
    generate_from_manifest(config, updated_manifest)
    generate_helper_wrappers(config)
    SnakeBridge.Registry.save()
    Lock.update(config)

    symbol_count = count_symbols(updated_manifest)
    file_count = length(config.libraries)
    Telemetry.compile_stop(start_time, symbol_count, file_count, libraries, :normal)
    {:ok, []}
  rescue
    e ->
      Telemetry.compile_exception(start_time, e, __STACKTRACE__)
      reraise e, __STACKTRACE__
  end
end
```

**Process:**
1. Scanner finds all Python library calls in code
2. Loads existing manifest from disk
3. Identifies missing symbols (detected - manifest)
4. Groups missing symbols by library and module into targets
5. Calls `update_manifest()` with targets
6. **Introspection happens but errors are silently ignored**
7. Saves incomplete manifest
8. Generates code from incomplete manifest
9. Returns success

---

## USER EXPERIENCE SCENARIO

**What the user sees:**

1. **Initial Compilation:**
   ```
   $ mix compile
   Compiling SnakeBridge bindings...
   Generated lib/snakebridge_generated/numpy.ex
   Compiled 8 files in 0.52s
   ```
   Success! But manifest is now incomplete.

2. **Later, in user code:**
   ```elixir
   defmodule MyApp do
     def process_data(data) do
       Numpy.special_func(data)  # This function wasn't introspected
     end
   end
   ```

3. **Runtime error:**
   ```
   ** (UndefinedFunctionError) function Numpy.special_func/1 is undefined
       (snakebridge) Numpy.special_func(data)
   ```

**Root cause is invisible** because:
- No error message during compilation
- No indication that introspection failed
- No log message about the failures
- Manifest was saved with gaps

---

## ERROR DETECTION CAPABILITIES

**What information is captured during error:**

1. **From IntrospectionError:**
   - Error type (package_not_found, import_error, timeout, introspection_bug)
   - Package name
   - Full error message
   - Python error output (for debugging)
   - Helpful suggestion

2. **From Batch Error (batch_error/4):**
   - Library label
   - Python module name
   - List of functions attempted
   - Underlying reason

3. **From Introspector:**
   - Timeout value
   - Execution status (exit code)
   - Stdout/stderr combined output

**Currently all this information is discarded in normal mode.**

---

## CODE REFERENCES SUMMARY

| Component | File | Lines | Role |
|-----------|------|-------|------|
| Main compile task | `lib/mix/tasks/compile/snakebridge.ex` | 1-874 | Orchestrates normal/strict mode |
| Error swallowing | `lib/mix/tasks/compile/snakebridge.ex` | 65-82 | Ignores introspection errors |
| Normal mode entry | `lib/mix/tasks/compile/snakebridge.ex` | 435-468 | Main normal mode flow |
| Strict mode entry | `lib/mix/tasks/compile/snakebridge.ex` | 405-433 | Strict mode verification |
| Batch introspection | `lib/snakebridge/introspector.ex` | 72-106 | Parallel introspection runner |
| Symbol introspection | `lib/snakebridge/introspector.ex` | 28-70 | Single module introspection |
| Error parsing | `lib/snakebridge/introspection_error.ex` | 1-116 | Error classification & formatting |
| Manifest operations | `lib/snakebridge/manifest.ex` | 1-314 | Manifest loading/saving |
| Scanner | `lib/snakebridge/scanner.ex` | 1-183 | Finds Python calls in code |
| Generator | `lib/snakebridge/generator.ex` | 1-400+ | Generates Elixir bindings |

---

## KEY FINDINGS

1. **Silent Failure:** Introspection errors are caught but completely ignored in normal mode
2. **No Visibility:** Users receive no indication that introspection failed
3. **Incomplete Artifacts:** Manifest and generated files are incomplete but marked as complete
4. **Delayed Detection:** Errors appear later at runtime in user code
5. **No Telemetry:** Errors are not emitted as telemetry events
6. **Good Error Infrastructure:** IntrospectionError provides excellent error classification and suggestions (unused in normal mode)
7. **Two-Mode Design:** Strict mode designed for CI (verify cached data), normal mode for local dev (regenerate data)
8. **Rich Context:** Batch errors capture library, module, and function names for diagnostics

---

## RECOMMENDATIONS FOR FIXING

1. **Logging:** Log introspection failures with full error details
2. **Telemetry:** Emit telemetry events for failures
3. **Partial Success Handling:** Track which functions succeeded vs failed
4. **Warnings:** Warn users about incomplete symbols using `Mix.shell().info/1`
5. **Strict-in-Normal Option:** Option to fail on first error in normal mode
6. **Better Error Context:** Include error details when saving manifest
7. **Recovery Guidance:** Provide actionable suggestions based on error type

---

**Document Generated:** 2025-12-31
