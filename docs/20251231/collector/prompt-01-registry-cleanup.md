# PROMPT 01: Registry Cleanup and Gitignore

**Target Version:** v0.8.7
**Issue ID:** RA-1
**Severity:** High
**Estimated Effort:** 15 minutes

---

## REQUIRED READING

Before starting, read these files to understand the context:

1. **Research Document:**
   - `/home/home/p/g/n/snakebridge/docs/20251231/registry-artifacts/research.md`

2. **Registry Module (understand the code, no changes needed):**
   - `/home/home/p/g/n/snakebridge/lib/snakebridge/registry.ex`

3. **Existing Registry Test:**
   - `/home/home/p/g/n/snakebridge/test/snakebridge/registry_integration_test.exs`

4. **Current Gitignore:**
   - `/home/home/p/g/n/snakebridge/.gitignore`

5. **Changelog (understand format):**
   - `/home/home/p/g/n/snakebridge/CHANGELOG.md`

---

## CONTEXT

SnakeBridge currently ships with pre-populated `priv/snakebridge/registry.json` files in 9 locations:

1. Main library: `/priv/snakebridge/registry.json`
2. Eight example projects: `examples/*/priv/snakebridge/registry.json`

This is problematic because:

1. **False implication of built-in adapters**: The registry contains generated content suggesting the library ships with pre-generated Python adapters (e.g., JSON bindings), but these adapters do not exist in the shipped package.

2. **Noisy git diffs**: Every `mix compile` updates registry timestamps and stats, creating unnecessary diffs for contributors.

3. **Architectural violation**: Generated artifacts should never be pre-populated or tracked in version control. The registry is regenerated during normal compile flow.

4. **Consumer confusion**: Users may think something is broken when their registry changes on first compile.

The registry is a **compile-time artifact** that is automatically generated when running `mix compile` via the `SnakeBridge.Registry.save()` call in the compile task. It is NOT used at runtime.

---

## GOAL

Remove all pre-populated registry.json files from version control and prevent future tracking.

### Success Criteria

1. All 9 registry.json files are deleted from the repository
2. `.gitignore` updated to prevent future tracking of registry.json files
3. New test verifies registry is created on compile when missing
4. All existing tests pass (`mix test`)
5. No dialyzer warnings (`mix dialyzer`)
6. No credo violations (`mix credo --strict`)
7. CHANGELOG.md updated for v0.8.7

---

## IMPLEMENTATION STEPS

### Step 1: Write Tests First (TDD)

Create a new test file at `/home/home/p/g/n/snakebridge/test/snakebridge/registry_file_test.exs`:

```elixir
defmodule SnakeBridge.RegistryFileTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Registry

  @registry_path Path.join([File.cwd!(), "priv", "snakebridge", "registry.json"])

  setup do
    # Backup existing registry if present
    backup_path = @registry_path <> ".backup"
    had_file = File.exists?(@registry_path)

    if had_file do
      File.copy!(@registry_path, backup_path)
    end

    Registry.clear()

    on_exit(fn ->
      Registry.clear()

      # Restore backup if it existed
      if had_file do
        File.rename!(backup_path, @registry_path)
      else
        File.rm(@registry_path)
      end
    end)

    :ok
  end

  describe "registry file lifecycle" do
    test "save/0 creates registry.json when file does not exist" do
      # Remove the file if it exists
      File.rm(@registry_path)
      refute File.exists?(@registry_path)

      # Register a library
      entry = %{
        python_module: "test_lib",
        python_version: "1.0.0",
        elixir_module: "TestLib",
        generated_at: DateTime.utc_now(),
        path: "/tmp/test",
        files: ["test.ex"],
        stats: %{functions: 1, classes: 0, submodules: 0}
      }

      :ok = Registry.register("test_lib", entry)

      # Save should create the file
      assert :ok = Registry.save()
      assert File.exists?(@registry_path)

      # Verify content is valid JSON
      {:ok, content} = File.read(@registry_path)
      {:ok, data} = Jason.decode(content)
      assert Map.has_key?(data, "libraries")
      assert Map.has_key?(data["libraries"], "test_lib")
    end

    test "load/0 handles missing registry.json gracefully" do
      # Remove the file
      File.rm(@registry_path)
      refute File.exists?(@registry_path)

      # Load should succeed with empty registry
      assert :ok = Registry.load()
      assert Registry.list_libraries() == []
    end

    test "registry directory is created if missing" do
      registry_dir = Path.dirname(@registry_path)

      # Temporarily remove the directory structure
      if File.exists?(@registry_path), do: File.rm!(@registry_path)
      if File.dir?(registry_dir), do: File.rmdir(registry_dir)

      entry = %{
        python_module: "test_lib",
        python_version: "1.0.0",
        elixir_module: "TestLib",
        generated_at: DateTime.utc_now(),
        path: "/tmp/test",
        files: ["test.ex"],
        stats: %{functions: 1, classes: 0, submodules: 0}
      }

      :ok = Registry.register("test_lib", entry)

      # Save should create the directory and file
      assert :ok = Registry.save()
      assert File.exists?(@registry_path)
    end
  end
end
```

Run the test to verify it passes:

```bash
mix test test/snakebridge/registry_file_test.exs
```

### Step 2: Update .gitignore

Add the following entry to `/home/home/p/g/n/snakebridge/.gitignore`:

```
# SnakeBridge generated registry (per-project artifact)
priv/snakebridge/registry.json
examples/*/priv/snakebridge/registry.json
```

Add this in the "SnakeBridge cache" section, after the existing entries.

### Step 3: Delete All Registry Files

Delete all 9 registry.json files using git rm to properly stage the deletions:

```bash
git rm --cached priv/snakebridge/registry.json
git rm --cached examples/class_constructor_example/priv/snakebridge/registry.json
git rm --cached examples/class_resolution_example/priv/snakebridge/registry.json
git rm --cached examples/math_demo/priv/snakebridge/registry.json
git rm --cached examples/proof_pipeline/priv/snakebridge/registry.json
git rm --cached examples/signature_showcase/priv/snakebridge/registry.json
git rm --cached examples/streaming_example/priv/snakebridge/registry.json
git rm --cached examples/telemetry_showcase/priv/snakebridge/registry.json
git rm --cached examples/wrapper_args_example/priv/snakebridge/registry.json
```

Then delete the actual files:

```bash
rm priv/snakebridge/registry.json
rm examples/class_constructor_example/priv/snakebridge/registry.json
rm examples/class_resolution_example/priv/snakebridge/registry.json
rm examples/math_demo/priv/snakebridge/registry.json
rm examples/proof_pipeline/priv/snakebridge/registry.json
rm examples/signature_showcase/priv/snakebridge/registry.json
rm examples/streaming_example/priv/snakebridge/registry.json
rm examples/telemetry_showcase/priv/snakebridge/registry.json
rm examples/wrapper_args_example/priv/snakebridge/registry.json
```

### Step 4: Update CHANGELOG.md

Add the following entry under the `## [Unreleased]` section. If there is no content under `[Unreleased]`, add the section headers:

```markdown
## [Unreleased]

## [0.8.7] - 2025-12-31

### Removed
- Pre-populated `priv/snakebridge/registry.json` files from repository; registry is now generated per-project during `mix compile`

### Changed
- Added `priv/snakebridge/registry.json` to `.gitignore` to prevent tracking of generated registry artifacts
```

---

## FILES TO MODIFY

| File | Action | Description |
|------|--------|-------------|
| `/home/home/p/g/n/snakebridge/.gitignore` | Edit | Add registry.json patterns |
| `/home/home/p/g/n/snakebridge/CHANGELOG.md` | Edit | Add v0.8.7 entry |
| `/home/home/p/g/n/snakebridge/test/snakebridge/registry_file_test.exs` | Create | New test file |

---

## FILES TO DELETE

Delete all 9 registry.json files:

1. `/home/home/p/g/n/snakebridge/priv/snakebridge/registry.json`
2. `/home/home/p/g/n/snakebridge/examples/class_constructor_example/priv/snakebridge/registry.json`
3. `/home/home/p/g/n/snakebridge/examples/class_resolution_example/priv/snakebridge/registry.json`
4. `/home/home/p/g/n/snakebridge/examples/math_demo/priv/snakebridge/registry.json`
5. `/home/home/p/g/n/snakebridge/examples/proof_pipeline/priv/snakebridge/registry.json`
6. `/home/home/p/g/n/snakebridge/examples/signature_showcase/priv/snakebridge/registry.json`
7. `/home/home/p/g/n/snakebridge/examples/streaming_example/priv/snakebridge/registry.json`
8. `/home/home/p/g/n/snakebridge/examples/telemetry_showcase/priv/snakebridge/registry.json`
9. `/home/home/p/g/n/snakebridge/examples/wrapper_args_example/priv/snakebridge/registry.json`

---

## CHANGELOG UPDATE

Add this exact text to CHANGELOG.md, replacing the existing `## [Unreleased]` section:

```markdown
## [Unreleased]

## [0.8.7] - 2025-12-31

### Removed
- Pre-populated `priv/snakebridge/registry.json` files from repository; registry is now generated per-project during `mix compile`

### Changed
- Added `priv/snakebridge/registry.json` to `.gitignore` to prevent tracking of generated registry artifacts
```

---

## VERIFICATION

After completing all steps, run these commands to verify the implementation:

### 1. Run All Tests

```bash
cd /home/home/p/g/n/snakebridge
mix test
```

Expected: All tests pass, including the new `registry_file_test.exs`.

### 2. Run Dialyzer

```bash
mix dialyzer
```

Expected: No warnings.

### 3. Run Credo

```bash
mix credo --strict
```

Expected: No violations.

### 4. Verify Registry Files Are Gone

```bash
find . -name "registry.json" -path "*/priv/snakebridge/*" 2>/dev/null
```

Expected: No output (no registry.json files exist).

### 5. Verify Gitignore Works

```bash
# Regenerate the main registry
mix compile

# Check that it's ignored
git status priv/snakebridge/registry.json
```

Expected: The file should not appear in git status (it's ignored).

### 6. Verify Git Staged Deletions

```bash
git status
```

Expected: You should see 9 deleted files staged for commit, the modified `.gitignore`, modified `CHANGELOG.md`, and the new test file.

---

## NOTES

- The `SnakeBridge.Registry` module code does NOT need modification. It already handles the case where the registry file doesn't exist gracefully (logs a debug message and starts with an empty registry).

- After this change, consumers of SnakeBridge will have their registry.json created on first `mix compile`. This is the correct behavior.

- Example projects will regenerate their registries when compiled locally, but these files will not be tracked in git.

---

## COMMIT MESSAGE

After verification, create a commit with this message:

```
fix(registry): remove pre-populated registry.json artifacts from git

Remove all 9 registry.json files that were incorrectly tracked in version
control. These files are compile-time artifacts that are regenerated
per-project during `mix compile` and should never be shipped or tracked.

- Delete priv/snakebridge/registry.json from main library
- Delete all examples/*/priv/snakebridge/registry.json files (8 total)
- Add registry.json patterns to .gitignore
- Add test verifying registry file creation on compile

This fixes issue RA-1 from the MVP critical fixes for v0.8.7.
```
