# REGISTRY ARTIFACTS RESEARCH: MVP-CRITICAL ISSUE #5

**Investigation Date:** December 31, 2025
**Scope:** Pre-populated registry.json files in shipped library
**Status:** Dangerous shipping practice identified

## EXECUTIVE SUMMARY

SnakeBridge currently ships with a pre-populated `priv/snakebridge/registry.json` file in the main library and all example projects. This is dangerous because:

1. **False implication of built-in adapters**: The registry contains generated content that suggests the library ships with pre-generated Python adapters
2. **Persistent git tracking**: Registry files are tracked in git across 8 example projects + the main library
3. **Consumer confusion**: When a consumer runs `mix compile`, their registry changes, creating unclear diffs
4. **Architectural violation**: Generated artifacts should never be pre-populated in a library

---

## CURRENT STATE ANALYSIS

### Registry Files in Repository

The repository currently tracks registry.json in 9 locations:

```
/priv/snakebridge/registry.json                                    (main library)
/examples/class_constructor_example/priv/snakebridge/registry.json
/examples/class_resolution_example/priv/snakebridge/registry.json
/examples/math_demo/priv/snakebridge/registry.json
/examples/proof_pipeline/priv/snakebridge/registry.json
/examples/signature_showcase/priv/snakebridge/registry.json
/examples/streaming_example/priv/snakebridge/registry.json
/examples/telemetry_showcase/priv/snakebridge/registry.json
/examples/wrapper_args_example/priv/snakebridge/registry.json
```

All 9 files are tracked in git and show as modified (`M`) in `git status`.

### Registry File Structure

**Main library registry (`priv/snakebridge/registry.json`):**
```json
{
  "generated_at": "2025-12-25T01:58:11.659134Z",
  "libraries": {
    "json": {
      "elixir_module": "Json",
      "files": [
        "json/_meta.ex",
        "json/classes/json_decode_error.ex",
        "json/classes/json_decoder.ex",
        "json/classes/json_encoder.ex",
        "json/json.ex"
      ],
      "generated_at": "2025-12-25T01:58:11.656624Z",
      "path": "lib/snakebridge/adapters/json",
      "python_module": "json",
      "python_version": "2.0",
      "stats": {
        "classes": 3,
        "functions": 4,
        "submodules": 0
      }
    }
  },
  "version": "2.1"
}
```

---

## HOW REGISTRY IS CREATED, READ, AND USED

### 1. Registry Creation (Compile-Time)

**File:** `lib/mix/tasks/compile/snakebridge.ex`

The compile task calls `SnakeBridge.Registry.save()` at line 456:

```elixir
defp run_normal(config) do
  # ... introspection and manifest building ...

  Manifest.save(config, updated_manifest)
  generate_from_manifest(config, updated_manifest)
  generate_helper_wrappers(config)
  SnakeBridge.Registry.save()  # <-- SAVES REGISTRY
  Lock.update(config)

  {:ok, []}
end
```

### 2. Registry Population (Compile-Time)

**File:** `lib/snakebridge/generator.ex`

During code generation, `Generator.generate_library/4` registers each generated library:

```elixir
def generate_library(library, functions, classes, config) do
  # ... generate code ...

  register_generated_library(library, functions, classes, config, path)

  :ok
end

defp register_generated_library(library, functions, classes, config, path) do
  entry = build_registry_entry(library, functions, classes, config, path)
  _ = SnakeBridge.Registry.register(library.python_name, entry)
end
```

### 3. Registry Storage

**File:** `lib/snakebridge/registry.ex`

The `SnakeBridge.Registry` module:
- **Loads** from `priv/snakebridge/registry.json` at startup
- **Saves** to `priv/snakebridge/registry.json` after compilation
- Uses `Application.get_env(:snakebridge, :registry_path)` or defaults to project path

### 4. Registry Usage at Runtime

**Current usage is MINIMAL to NONE:**

The registry is NOT used at runtime by SnakeBridge or consumer applications. It exists purely as a compile-time artifact.

The `Application` module does NOT start a Registry agent:
- Only starts `SnakeBridge.SessionManager` and `SnakeBridge.CallbackRegistry`

---

## WHAT IS SHIPPED VS GENERATED

### What Gets Published to Hex

**File:** `mix.exs` lines 90-106:

```elixir
defp package do
  [
    name: "snakebridge",
    files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md assets),
    exclude_patterns: [
      "priv/python/.pytest_cache",
      "**/.pytest_cache",
      "priv/python/__pycache__",
      "**/__pycache__"
    ],
    ...
  ]
end
```

**The package includes `priv/` directory**, which means:
- `priv/snakebridge/registry.json` IS shipped to Hex
- Pre-populated with JSON bindings from library's own introspection
- Creates false expectation that these adapters are "built-in"

---

## THE PROBLEM IN DETAIL

### Problem 1: False Implication of Built-in Adapters

The main library ships with a registry containing JSON bindings at specific file paths:
```
path: "lib/snakebridge/adapters/json"
files: [
  "json/_meta.ex",
  "json/classes/json_decode_error.ex",
  ...
]
```

But these files don't exist in the shipped library. This creates confusion:
- Users think SnakeBridge comes with pre-built adapters
- The registry claims there are adapters in old multi-file structure
- Actual generated code goes to `lib/snakebridge_generated/` (single files per library)

### Problem 2: Registry Changes on Every Compile

Every consumer project's `mix compile` updates their registry.json with:
- New `generated_at` timestamps
- Updated file lists and stats
- Diffs that are noisy and unnecessary

### Problem 3: Architectural Mismatch

Current architecture:
- Registry stored in `priv/` (shipped with library)
- But registry is project-specific (list of libraries configured in project's mix.exs)
- Generated artifacts mixed with shipped artifacts

### Problem 4: Registry Not Used at Runtime

The registry provides runtime introspection but:
- SnakeBridge runtime code doesn't call it
- Consumer code doesn't call it
- Only testing code exercises it

---

## RECOMMENDATIONS

### Immediate Actions (MVP Critical)

1. **Remove pre-populated registries from git**
   - Delete `priv/snakebridge/registry.json` from the main library
   - Delete `examples/*/priv/snakebridge/registry.json` from all examples

2. **Update .gitignore**
   Add to `.gitignore`:
   ```
   # SnakeBridge generated registry
   priv/snakebridge/registry.json
   ```

3. **Document registry.json as generated artifact**
   - Update CHANGELOG noting that registry.json is now generated per-project
   - Add comment in Registry module that file is auto-generated

---

## IMPLEMENTATION CHECKLIST

- [ ] Delete `/priv/snakebridge/registry.json`
- [ ] Delete all `examples/*/priv/snakebridge/registry.json` (8 files)
- [ ] Add entry to `.gitignore` for `priv/snakebridge/registry.json`
- [ ] Update CHANGELOG with "Removed pre-populated registry artifacts"
- [ ] Run `mix compile` on main library and verify registry is recreated
- [ ] Run `mix compile` on example projects and verify registries are created
- [ ] Update documentation explaining registry is project-generated
- [ ] Test that CI passes without pre-populated registries

---

## FILES INVOLVED

**Files to change:**
- `.gitignore` - Add registry.json pattern
- `CHANGELOG.md` - Document removal

**Files to delete:**
- `/priv/snakebridge/registry.json`
- `/examples/class_constructor_example/priv/snakebridge/registry.json`
- `/examples/class_resolution_example/priv/snakebridge/registry.json`
- `/examples/math_demo/priv/snakebridge/registry.json`
- `/examples/proof_pipeline/priv/snakebridge/registry.json`
- `/examples/signature_showcase/priv/snakebridge/registry.json`
- `/examples/streaming_example/priv/snakebridge/registry.json`
- `/examples/telemetry_showcase/priv/snakebridge/registry.json`
- `/examples/wrapper_args_example/priv/snakebridge/registry.json`

**Files that handle registry (no changes needed):**
- `lib/snakebridge/registry.ex`
- `lib/mix/tasks/compile/snakebridge.ex`
- `lib/snakebridge/generator.ex`
- `mix.exs` (package definition)

---

## CONCLUSION

The pre-populated registry artifacts are an MVP-critical issue because they:
1. Create false implications about what the library ships
2. Generate noisy git diffs for every consumer
3. Violate clean architecture principles
4. Serve no functional purpose

Removing them is straightforward and low-risk: the registry is automatically regenerated during the normal compile flow.

---

**Document Generated:** 2025-12-31
