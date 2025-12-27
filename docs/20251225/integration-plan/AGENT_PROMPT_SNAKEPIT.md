# Agent Prompt: Implement Snakepit.PythonPackages

## Mission

Implement the `Snakepit.PythonPackages` module to provide package installation
and management for Snakepit-managed Python environments. This closes a critical
gap needed for SnakeBridge UV integration.

## Required Reading

### Design Documents (Read First)

1. `/home/home/p/g/n/snakebridge/docs/20251225/snakebridge-snakepit-uv-integration.md`
   - The original UV integration proposal
   - Pay attention to the `Snakepit.PythonPackages` API specification

2. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/00-executive-summary.md`
   - Overview of gaps and recommended path

3. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/01-gap-analysis.md`
   - Specific gaps between SnakeBridge and Snakepit
   - Section 3 (Package Installation) is critical

4. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/02-uv-integration-critique.md`
   - Critique of the UV design with 10 improvements
   - Incorporate the recommendations

5. `/home/home/p/g/n/snakebridge/docs/20251225/integration-plan/04-implementation-plan.md`
   - Phase 1 contains the implementation skeleton for `Snakepit.PythonPackages`
   - Use this as a starting point but adapt as needed

### Snakepit Source Code (Understand the Codebase)

The Snakepit project is at `/home/home/p/g/n/snakepit/`

**Core modules to understand:**

1. `/home/home/p/g/n/snakepit/lib/snakepit/python_runtime.ex`
   - Existing UV-managed Python runtime support
   - `resolve_executable/0` - returns Python path and metadata
   - `runtime_env/0` - returns environment variables
   - `install_managed/2` - installs Python via UV
   - Your module will integrate with this

2. `/home/home/p/g/n/snakepit/lib/snakepit/config.ex`
   - Configuration system
   - Add new `:python_packages` config section

3. `/home/home/p/g/n/snakepit/lib/snakepit/bootstrap.ex`
   - Current bootstrap using pip+venv
   - Consider how PythonPackages relates to this
   - May need to refactor Bootstrap to use PythonPackages internally

4. `/home/home/p/g/n/snakepit/lib/snakepit/error.ex`
   - Existing error structure
   - Create `Snakepit.PackageError` following this pattern

5. `/home/home/p/g/n/snakepit/mix.exs`
   - Current version and dependencies

**Test patterns to follow:**

6. `/home/home/p/g/n/snakepit/test/snakepit/python_runtime_test.exs`
   - Testing patterns for Python-related functionality

### SnakeBridge Context (Understand the Consumer)

7. `/home/home/p/g/n/snakebridge/lib/snakebridge/python_runner/system.ex`
   - How SnakeBridge currently uses Snakepit.PythonRuntime
   - Your module will be used similarly

## What to Implement

### 1. New Module: `Snakepit.PythonPackages`

Location: `/home/home/p/g/n/snakepit/lib/snakepit/python_packages.ex`

**Required Functions:**

```elixir
@spec ensure!(requirements_spec(), keyword()) :: :ok | no_return()
# Ensures all packages are installed. Raises on failure.
# Options: :upgrade, :quiet, :timeout

@spec check_installed([String.t()], keyword()) ::
  {:ok, :all_installed} | {:ok, {:missing, [String.t()]}}
# Checks which packages are installed without installing.

@spec lock_metadata([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
# Returns metadata for lockfile (package name → version, hash).

@spec installer() :: :uv | :pip
# Returns which installer is being used.

@spec install!([String.t()], keyword()) :: :ok | no_return()
# Installs packages (internal, but testable).
```

**Requirements Spec Types:**

```elixir
@type requirement :: String.t()  # PEP-440 format: "numpy~=1.26", "torch>=2.0"
@type requirements_spec ::
  {:list, [requirement()]} |
  {:file, Path.t()}
```

### 2. New Error Module: `Snakepit.PackageError`

Location: `/home/home/p/g/n/snakepit/lib/snakepit/package_error.ex`

```elixir
defexception [:type, :packages, :message, :suggestion, :output]

@type t :: %__MODULE__{
  type: :not_installed | :install_failed | :version_mismatch | :invalid_requirement,
  packages: [String.t()],
  message: String.t(),
  suggestion: String.t() | nil,
  output: String.t() | nil
}
```

### 3. Config Extension

Add to `/home/home/p/g/n/snakepit/lib/snakepit/config.ex`:

```elixir
config :snakepit, :python_packages,
  installer: :auto,  # :uv | :pip | :auto (detect)
  timeout: 300_000,  # 5 minutes default
  env: %{
    "PYTHONNOUSERSITE" => "1",
    "PIP_DISABLE_PIP_VERSION_CHECK" => "1",
    "PIP_NO_INPUT" => "1"
  }
```

### 4. Tests

Location: `/home/home/p/g/n/snakepit/test/snakepit/python_packages_test.exs`

Required test cases:
- `ensure!/2` with valid packages
- `ensure!/2` with invalid packages (raises)
- `check_installed/2` when all installed
- `check_installed/2` when some missing
- `lock_metadata/2` returns correct format
- `installer/0` detection logic
- UV vs pip fallback behavior
- Timeout handling
- Requirement parsing (file vs list)

### 5. Documentation

- Add `@moduledoc` and `@doc` to all public functions
- Add usage examples in moduledoc
- Update `/home/home/p/g/n/snakepit/README.md` with new functionality

## Implementation Guidelines

### Use TDD

1. Write failing test first
2. Implement minimum code to pass
3. Refactor
4. Repeat

### Environment Variables for Testing

Use environment isolation in tests:
```elixir
setup do
  # Save original config
  original = Application.get_env(:snakepit, :python_packages)
  on_exit(fn -> Application.put_env(:snakepit, :python_packages, original) end)
end
```

### UV Detection

```elixir
defp detect_installer do
  case System.find_executable("uv") do
    nil -> :pip
    _path -> :uv
  end
end
```

### Package Detection (UV)

```bash
uv pip show <package> --python /path/to/python
# Exit 0 if installed, non-zero if not
```

### Package Detection (pip)

```bash
/path/to/python -m pip show <package>
# Exit 0 if installed, non-zero if not
```

### Lock Metadata (UV)

```bash
uv pip freeze --python /path/to/python
# Returns: package==version lines
```

### Lock Metadata (pip)

```bash
/path/to/python -m pip freeze
# Returns: package==version lines
```

### Error Handling

Always wrap shell command failures in `Snakepit.PackageError`:

```elixir
case System.cmd("uv", args, opts) do
  {_output, 0} -> :ok
  {output, code} ->
    raise Snakepit.PackageError,
      type: :install_failed,
      packages: packages,
      message: "UV install failed with exit code #{code}",
      output: output,
      suggestion: "Check package names and network connectivity"
end
```

## Quality Requirements

Before considering the work complete:

### 1. No Warnings

```bash
cd /home/home/p/g/n/snakepit
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

### 1. Update `/home/home/p/g/n/snakepit/mix.exs`

Change version from `0.7.x` to `0.8.0` (minor bump for new feature).

### 2. Update `/home/home/p/g/n/snakepit/README.md`

Update any version references.

### 3. Create/Update CHANGELOG

Location: `/home/home/p/g/n/snakepit/CHANGELOG.md`

Add entry:

```markdown
## [0.8.0] - 2025-12-25

### Added
- `Snakepit.PythonPackages` module for UV/pip package management
- `Snakepit.PackageError` structured error type
- Configuration for `:python_packages` in application env
- `ensure!/2` - Install packages if missing
- `check_installed/2` - Check package installation status
- `lock_metadata/2` - Get package versions for lockfiles

### Changed
- (list any changes to existing behavior)
```

## Example Usage (for README/docs)

```elixir
# Ensure packages are installed
Snakepit.PythonPackages.ensure!({:list, ["numpy~=1.26", "scipy~=1.11"]})

# Check what's installed
case Snakepit.PythonPackages.check_installed(["numpy", "pandas"]) do
  {:ok, :all_installed} ->
    IO.puts("Ready!")
  {:ok, {:missing, packages}} ->
    IO.puts("Missing: #{inspect(packages)}")
end

# Get metadata for lockfile
{:ok, metadata} = Snakepit.PythonPackages.lock_metadata(["numpy", "scipy"])
# => %{"numpy" => %{version: "1.26.4"}, "scipy" => %{version: "1.11.4"}}

# Install from requirements file
Snakepit.PythonPackages.ensure!({:file, "requirements.txt"}, upgrade: true)
```

## Deliverables Checklist

- [ ] `lib/snakepit/python_packages.ex` - Main module
- [ ] `lib/snakepit/package_error.ex` - Error struct
- [ ] `test/snakepit/python_packages_test.exs` - Tests
- [ ] Config extension in `lib/snakepit/config.ex`
- [ ] Updated `README.md`
- [ ] Updated `CHANGELOG.md`
- [ ] Version bump in `mix.exs`
- [ ] All tests pass
- [ ] No warnings
- [ ] Dialyzer clean
- [ ] Credo strict clean
- [ ] Code formatted

## Notes

- Focus on correctness over cleverness
- Use existing patterns from the codebase
- If you encounter ambiguity, prefer the simpler solution
- The module should work without SnakeBridge (it's a Snakepit feature)
- UV is preferred but pip fallback must work
