# Agent Prompt: Implement SnakeBridge UV Integration

## Mission

Implement the SnakeBridge side of UV integration: `SnakeBridge.PythonEnv`
orchestrator, config extensions, strict mode enforcement, lockfile extension,
setup mix task, and introspection error classification.

**Snakepit 0.7.5 is now available** with `Snakepit.PythonPackages` module ready
to use.

## Required Reading

### Design Documents (Read First)

1. `/home/home/p/g/n/snakebridge/docs/20251225/snakebridge-snakepit-uv-integration.md`
   - The original UV integration proposal
   - Pay attention to `SnakeBridge.PythonEnv` API specification

2. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/00-executive-summary.md`
   - Overview of gaps and recommended path

3. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/01-gap-analysis.md`
   - Specific gaps - sections 4, 5, 6, 7, 9 are your responsibility

4. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/02-uv-integration-critique.md`
   - Critique with improvements - incorporate recommendations

5. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/03-essential-enhancements.md`
   - P0 items 2, 3, 4 and P1 item 5 are your scope

6. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/04-implementation-plan.md`
   - Phases 2-6 contain implementation skeletons
   - Use as starting point but adapt as needed

7. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/05-determinism-strategy.md`
   - Lockfile determinism requirements

### SnakeBridge Source Code (Understand the Codebase)

The project is at `/home/home/p/g/n/snakebridge/`

**Core modules to understand and modify:**

1. `/home/home/p/g/n/snakebridge/lib/snakebridge/config.ex`
   - Current config structure
   - Add `pypi_package` and `extras` to `Config.Library`
   - Add `auto_install` setting

2. `/home/home/p/g/n/snakebridge/lib/mix/tasks/compile/snakebridge.ex`
   - Current compiler task
   - Add strict mode enforcement
   - Integrate PythonEnv.ensure!

3. `/home/home/p/g/n/snakebridge/lib/snakebridge/lock.ex`
   - Current lockfile implementation
   - Extend with package identity

4. `/home/home/p/g/n/snakebridge/lib/snakebridge/introspector.ex`
   - Current introspection logic
   - Improve error classification

5. `/home/home/p/g/n/snakebridge/lib/snakebridge/manifest.ex`
   - Manifest handling (reference for patterns)

6. `/home/home/p/g/n/snakebridge/lib/snakebridge/python_runner/system.ex`
   - How SnakeBridge currently uses Snakepit

**Test patterns to follow:**

7. `/home/home/p/g/n/snakebridge/test/snakebridge/config_test.exs`
8. `/home/home/p/g/n/snakebridge/test/snakebridge/lock_test.exs`
9. `/home/home/p/g/n/snakebridge/test/snakebridge/introspector_test.exs`

**Examples to update:**

10. `/home/home/p/g/n/snakebridge/examples/math_demo/`
11. `/home/home/p/g/n/snakebridge/examples/proof_pipeline/`

### Snakepit 0.7.5 API (Now Available)

The following Snakepit functions are now available for use:

```elixir
# Install packages
Snakepit.PythonPackages.ensure!({:list, ["numpy~=1.26"]}, opts)
Snakepit.PythonPackages.ensure!({:file, "requirements.txt"}, opts)

# Check installation status
Snakepit.PythonPackages.check_installed(["numpy", "scipy"])
# => {:ok, :all_installed} | {:ok, {:missing, ["scipy"]}}

# Get metadata for lockfile
Snakepit.PythonPackages.lock_metadata(["numpy"])
# => {:ok, %{"numpy" => %{version: "1.26.4"}}}

# Check which installer
Snakepit.PythonPackages.installer()
# => :uv | :pip
```

## What to Implement

### 1. New Module: `SnakeBridge.PythonEnv`

Location: `/home/home/p/g/n/snakebridge/lib/snakebridge/python_env.ex`

**Required Functions:**

```elixir
@spec ensure!(Config.t()) :: :ok | no_return()
# Ensures Python environment is ready for introspection.
# In dev with auto_install: installs missing packages.
# In strict mode: verifies environment, raises if not ready.

@spec derive_requirements([Config.Library.t()]) :: [String.t()]
# Converts library config to PEP-440 requirement strings.
# Handles pypi_package overrides, extras, version translation.
# Skips :stdlib libraries.

@spec verify_environment!(Config.t()) :: :ok | no_return()
# Checks packages are installed without installing.
# Raises SnakeBridge.EnvironmentError if missing.
```

### 2. New Error Module: `SnakeBridge.EnvironmentError`

Location: `/home/home/p/g/n/snakebridge/lib/snakebridge/environment_error.ex`

```elixir
defexception [:message, :missing_packages, :suggestion]

@type t :: %__MODULE__{
  message: String.t(),
  missing_packages: [String.t()],
  suggestion: String.t()
}
```

### 3. New Error Module: `SnakeBridge.IntrospectionError`

Location: `/home/home/p/g/n/snakebridge/lib/snakebridge/introspection_error.ex`

```elixir
defexception [:type, :package, :message, :python_error, :suggestion]

@type t :: %__MODULE__{
  type: :package_not_found | :import_error | :timeout | :introspection_bug,
  package: String.t() | nil,
  message: String.t(),
  python_error: String.t() | nil,
  suggestion: String.t() | nil
}

@spec from_python_output(String.t(), String.t()) :: t()
# Parses Python stderr to classify the error.
```

### 4. Config Extension

Modify `/home/home/p/g/n/snakebridge/lib/snakebridge/config.ex`:

**Extend Config.Library struct:**

```elixir
defmodule Config.Library do
  defstruct [
    :name,
    :version,
    :module_name,
    :python_name,
    :pypi_package,      # NEW - PyPI package name if different from python_name
    :extras,            # NEW - List of extras like ["cuda", "dev"]
    :include,
    :exclude,
    :streaming,
    :submodules
  ]
end
```

**Add to main Config struct:**

```elixir
defstruct [
  # ... existing fields ...
  :auto_install,  # NEW - :never | :dev | :always (default :dev)
]
```

**Update parsing to handle new fields.**

### 5. Strict Mode Enforcement

Modify `/home/home/p/g/n/snakebridge/lib/mix/tasks/compile/snakebridge.ex`:

```elixir
def run(_args) do
  config = Config.load()

  if strict_mode?(config) do
    run_strict(config)
  else
    # Ensure environment before introspection
    SnakeBridge.PythonEnv.ensure!(config)
    run_normal(config)
  end
end

defp strict_mode?(config) do
  System.get_env("SNAKEBRIDGE_STRICT") == "1" || config.strict == true
end

defp run_strict(config) do
  # 1. Load manifest
  # 2. Scan project
  # 3. If missing symbols -> FAIL with clear message
  # 4. Never run Python introspection
  # 5. Compile existing generated files normally
end
```

### 6. Lockfile Extension

Modify `/home/home/p/g/n/snakebridge/lib/snakebridge/lock.ex`:

**Extend lock structure:**

```elixir
%{
  "version" => "0.4.x",
  "environment" => %{
    # ... existing fields ...
    "python_packages_hash" => "sha256:..."  # NEW
  },
  "libraries" => %{...},
  "python_packages" => %{  # NEW
    "numpy" => %{"version" => "1.26.4"},
    "scipy" => %{"version" => "1.11.4"}
  }
}
```

**Add functions:**

```elixir
@spec compute_packages_hash(map()) :: String.t()
# Deterministic hash from sorted package versions.

@spec get_package_metadata(Config.t()) :: map()
# Calls Snakepit.PythonPackages.lock_metadata/2.
```

### 7. New Mix Task: `mix snakebridge.setup`

Location: `/home/home/p/g/n/snakebridge/lib/mix/tasks/snakebridge.setup.ex`

```elixir
defmodule Mix.Tasks.Snakebridge.Setup do
  @shortdoc "Provision Python environment for SnakeBridge"
  @moduledoc """
  Provisions the Python environment for SnakeBridge introspection.

  ## Usage

      mix snakebridge.setup

  ## Options

      --upgrade    Upgrade packages to latest matching versions
      --verbose    Show detailed output
      --check      Only check, don't install (exit 1 if missing)
  """

  use Mix.Task

  def run(args) do
    # Parse options
    # Load config
    # Derive requirements
    # If --check: verify only
    # Else: install via Snakepit.PythonPackages.ensure!
  end
end
```

### 8. Update Introspector Error Handling

Modify `/home/home/p/g/n/snakebridge/lib/snakebridge/introspector.ex`:

When Python introspection fails, classify the error:

```elixir
defp handle_python_error(output, package) do
  {:error, SnakeBridge.IntrospectionError.from_python_output(output, package)}
end
```

### 9. Tests

Create/update test files:

- `/home/home/p/g/n/snakebridge/test/snakebridge/python_env_test.exs`
- `/home/home/p/g/n/snakebridge/test/snakebridge/environment_error_test.exs`
- `/home/home/p/g/n/snakebridge/test/snakebridge/introspection_error_test.exs`
- `/home/home/p/g/n/snakebridge/test/mix/tasks/snakebridge.setup_test.exs`
- Update `/home/home/p/g/n/snakebridge/test/snakebridge/config_test.exs` for new fields
- Update `/home/home/p/g/n/snakebridge/test/snakebridge/lock_test.exs` for package hash

**Test cases for PythonEnv:**
- derive_requirements with stdlib (should skip)
- derive_requirements with version constraints
- derive_requirements with pypi_package override
- derive_requirements with extras
- ensure! in dev mode (calls Snakepit)
- ensure! in strict mode (verifies only)
- verify_environment! when all installed
- verify_environment! when missing (raises)

**Test cases for strict mode:**
- Compile with missing symbols fails
- Compile with all symbols present succeeds
- SNAKEBRIDGE_STRICT=1 env var works

**Test cases for lockfile:**
- Package hash is deterministic
- Package metadata included in lock
- Lock format is valid

### 10. Update Examples

Update `/home/home/p/g/n/snakebridge/examples/math_demo/`:
- Add example with pypi_package override if applicable
- Ensure examples work with new setup flow

### 11. Documentation

- Add `@moduledoc` and `@doc` to all new public functions
- Update `/home/home/p/g/n/snakebridge/README.md`:
  - Add `mix snakebridge.setup` documentation
  - Document new config options (pypi_package, extras, auto_install)
  - Document strict mode workflow for CI

## Implementation Guidelines

### Use TDD

1. Write failing test first
2. Implement minimum code to pass
3. Refactor
4. Repeat

### Version Constraint Translation

Elixir `~>` to PEP-440 `~=`:

```elixir
defp translate_version(nil), do: nil
defp translate_version(:stdlib), do: nil
defp translate_version(v) when is_binary(v) do
  # If already PEP-440, use as-is
  if String.starts_with?(v, ["~=", ">=", "<=", "==", "!="]) do
    v
  else
    # Translate ~> X.Y to ~=X.Y
    case Regex.run(~r/^~>\s*(.+)$/, v) do
      [_, ver] -> "~=#{ver}"
      nil -> "==#{v}"
    end
  end
end
```

### Strict Mode Error Message

```
** (SnakeBridge.CompileError) Strict mode: 3 symbol(s) not in manifest.

Missing:
  - Numpy.array/1
  - Numpy.zeros/2
  - Scipy.integrate/3

To fix:
  1. Run `mix snakebridge.setup` locally
  2. Run `mix compile` to generate bindings
  3. Commit the updated manifest and generated files
  4. Re-run CI

Set SNAKEBRIDGE_STRICT=0 to disable strict mode.
```

### Package Hash Determinism

```elixir
def compute_packages_hash(packages) when is_map(packages) do
  packages
  |> Enum.sort_by(fn {name, _} -> name end)
  |> Enum.map(fn {name, %{"version" => v}} -> "#{name}==#{v}" end)
  |> Enum.join("\n")
  |> then(&:crypto.hash(:sha256, &1))
  |> Base.encode16(case: :lower)
end
```

## Quality Requirements

Before considering the work complete:

### 1. No Warnings

```bash
cd /home/home/p/g/n/snakebridge
mix compile --warnings-as-errors
```

### 2. All Tests Pass

```bash
mix test
```

### 3. Dialyzer Clean

```bash
mix dialyzer
```

### 4. Credo Strict Clean

```bash
mix credo --strict
```

### 5. Format Check

```bash
mix format --check-formatted
```

## Version Bump

After all quality checks pass:

### 1. Update `/home/home/p/g/n/snakebridge/mix.exs`

Change version from `0.4.0` to `0.5.0` (minor bump for new features).

### 2. Update `/home/home/p/g/n/snakebridge/README.md`

Update any version references.

### 3. Create/Update CHANGELOG

Location: `/home/home/p/g/n/snakebridge/CHANGELOG.md`

Add entry:

```markdown
## [0.5.0] - 2025-12-25

### Added
- `SnakeBridge.PythonEnv` module for Python environment orchestration
- `SnakeBridge.EnvironmentError` for missing package errors
- `SnakeBridge.IntrospectionError` for classified introspection failures
- `mix snakebridge.setup` task for provisioning Python packages
- Config options: `pypi_package`, `extras` per library
- Config option: `auto_install` (:never | :dev | :always)
- Strict mode enforcement via `SNAKEBRIDGE_STRICT=1` or `strict: true`
- Package identity in `snakebridge.lock` (`python_packages`, `python_packages_hash`)

### Changed
- Compiler now calls `PythonEnv.ensure!/1` before introspection (when not strict)
- Improved introspection error messages with fix suggestions

### Dependencies
- Requires snakepit ~> 0.7.5 (for PythonPackages support)
```

## Deliverables Checklist

- [ ] `lib/snakebridge/python_env.ex` - Environment orchestrator
- [ ] `lib/snakebridge/environment_error.ex` - Missing packages error
- [ ] `lib/snakebridge/introspection_error.ex` - Classified introspection errors
- [ ] `lib/mix/tasks/snakebridge.setup.ex` - Setup mix task
- [ ] Updated `lib/snakebridge/config.ex` - pypi_package, extras, auto_install
- [ ] Updated `lib/snakebridge/lock.ex` - Package identity
- [ ] Updated `lib/mix/tasks/compile/snakebridge.ex` - Strict mode, PythonEnv
- [ ] Updated `lib/snakebridge/introspector.ex` - Error classification
- [ ] `test/snakebridge/python_env_test.exs`
- [ ] `test/snakebridge/environment_error_test.exs`
- [ ] `test/snakebridge/introspection_error_test.exs`
- [ ] `test/mix/tasks/snakebridge.setup_test.exs`
- [ ] Updated config and lock tests
- [ ] Updated examples (if needed)
- [ ] Updated `README.md`
- [ ] Created/updated `CHANGELOG.md`
- [ ] Version bump in `mix.exs`
- [ ] All tests pass
- [ ] No warnings
- [ ] Dialyzer clean
- [ ] Credo strict clean
- [ ] Code formatted

## Notes

- Snakepit 0.7.5 is already set as dependency in mix.exs
- Focus on correctness over cleverness
- Use existing patterns from the codebase
- The strict mode workflow is critical for CI safety
- Lockfile determinism is essential - no timestamps, sorted keys
- All new public functions need @doc and @spec
