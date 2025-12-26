# Implementation Plan

Status: Planning
Date: 2025-12-25

## Overview

This document provides concrete implementation steps for the P0 essential
enhancements identified in the analysis.

## Phase 1: Snakepit.PythonPackages

**Owner**: Snakepit
**Effort**: 2-3 days

### New File: `lib/snakepit/python_packages.ex`

```elixir
defmodule Snakepit.PythonPackages do
  @moduledoc """
  Package installation and management for Snakepit-managed Python environments.

  Uses UV when available, falls back to pip.
  """

  alias Snakepit.PythonRuntime

  @type requirement :: String.t()
  @type requirements_spec ::
    {:list, [requirement()]} |
    {:file, Path.t()}

  @doc """
  Ensures all packages in the spec are installed.

  Options:
    - :upgrade - Upgrade packages to latest matching version (default: false)
    - :quiet - Suppress output (default: false)
    - :timeout - Installation timeout in ms (default: 300_000)
  """
  @spec ensure!(requirements_spec(), keyword()) :: :ok
  def ensure!(spec, opts \\ []) do
    requirements = normalize_spec(spec)

    case check_installed(requirements, opts) do
      {:ok, :all_installed} -> :ok
      {:ok, {:missing, missing}} -> install!(missing, opts)
    end
  end

  @doc """
  Checks which packages are installed.

  Returns `{:ok, :all_installed}` or `{:ok, {:missing, [package]}}`.
  """
  @spec check_installed([requirement()], keyword()) ::
    {:ok, :all_installed} | {:ok, {:missing, [requirement()]}}
  def check_installed(requirements, opts \\ [])

  @doc """
  Returns metadata about installed packages for lockfile.

  Returns map of package name to version and hash.
  """
  @spec lock_metadata([requirement()], keyword()) ::
    {:ok, map()} | {:error, term()}
  def lock_metadata(requirements, opts \\ [])

  @doc """
  Returns the installer being used (:uv or :pip).
  """
  @spec installer() :: :uv | :pip
  def installer do
    config = Application.get_env(:snakepit, :python_packages, [])
    Keyword.get(config, :installer, detect_installer())
  end

  # Private implementation

  defp normalize_spec({:list, reqs}), do: reqs
  defp normalize_spec({:file, path}) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp detect_installer do
    case System.find_executable("uv") do
      nil -> :pip
      _ -> :uv
    end
  end

  defp install!(packages, opts) do
    case installer() do
      :uv -> install_with_uv!(packages, opts)
      :pip -> install_with_pip!(packages, opts)
    end
  end

  defp install_with_uv!(packages, opts) do
    {:ok, python, _meta} = PythonRuntime.resolve_executable()

    args = [
      "pip", "install",
      "--python", python
    ] ++ build_install_args(opts) ++ packages

    env = build_env()
    timeout = Keyword.get(opts, :timeout, 300_000)

    case System.cmd("uv", args, env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> raise "UV install failed (#{code}): #{output}"
    end
  end

  defp install_with_pip!(packages, opts) do
    {:ok, python, _meta} = PythonRuntime.resolve_executable()

    args = [
      "-m", "pip", "install"
    ] ++ build_install_args(opts) ++ packages

    env = build_env()
    timeout = Keyword.get(opts, :timeout, 300_000)

    case System.cmd(python, args, env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> raise "Pip install failed (#{code}): #{output}"
    end
  end

  defp build_install_args(opts) do
    args = []
    args = if Keyword.get(opts, :upgrade), do: ["--upgrade" | args], else: args
    args = if Keyword.get(opts, :quiet), do: ["--quiet" | args], else: args
    args
  end

  defp build_env do
    %{
      "PYTHONNOUSERSITE" => "1",
      "PIP_DISABLE_PIP_VERSION_CHECK" => "1",
      "PIP_NO_INPUT" => "1",
      "PIP_NO_WARN_SCRIPT_LOCATION" => "1",
      "UV_NO_PROGRESS" => "1"
    }
  end
end
```

### Implementation Notes

1. **check_installed/2**: Use `uv pip show` or `pip show` for each package
2. **lock_metadata/2**: Use `uv pip freeze` to get resolved versions
3. **Error handling**: Wrap in `Snakepit.PackageError` struct

### Tests Required

- `test/snakepit/python_packages_test.exs`
  - Installing a single package
  - Installing from requirements file
  - Detecting already-installed packages
  - Upgrade behavior
  - UV vs pip fallback
  - Error handling for invalid packages

---

## Phase 2: SnakeBridge.PythonEnv

**Owner**: SnakeBridge
**Effort**: 1 day

### New File: `lib/snakebridge/python_env.ex`

```elixir
defmodule SnakeBridge.PythonEnv do
  @moduledoc """
  Compile-time orchestrator for Python environment provisioning.

  Ensures the Snakepit-managed Python environment has the required
  packages before SnakeBridge introspects.
  """

  alias SnakeBridge.Config

  @doc """
  Ensures the Python environment is ready for introspection.

  In dev mode with auto_install enabled:
  1. Ensures managed Python is installed (if configured)
  2. Ensures required packages are installed

  In strict mode:
  Fails if environment is not already set up.
  """
  @spec ensure!(Config.t()) :: :ok | no_return()
  def ensure!(config) do
    if should_auto_install?(config) do
      do_ensure!(config)
    else
      verify_environment!(config)
    end
  end

  @doc """
  Derives Python requirements from library configuration.

  Handles:
  - Version constraints (Elixir ~> to PEP-440 ~=)
  - PyPI package name overrides
  - Extras
  - Skipping :stdlib libraries
  """
  @spec derive_requirements([Config.Library.t()]) :: [String.t()]
  def derive_requirements(libraries) do
    libraries
    |> Enum.reject(&(&1.version == :stdlib))
    |> Enum.map(&library_to_requirement/1)
  end

  # Private implementation

  defp should_auto_install?(config) do
    auto_install = get_auto_install_setting(config)

    case auto_install do
      :never -> false
      :always -> true
      :dev -> Mix.env() == :dev
    end
  end

  defp get_auto_install_setting(config) do
    env_override = System.get_env("SNAKEBRIDGE_AUTO_INSTALL")

    cond do
      env_override == "never" -> :never
      env_override == "always" -> :always
      env_override == "dev" -> :dev
      true -> Map.get(config, :auto_install, :dev)
    end
  end

  defp do_ensure!(config) do
    # Step 1: Ensure managed Python if configured
    ensure_python_runtime!()

    # Step 2: Derive and install packages
    requirements = derive_requirements(config.libraries)

    if requirements != [] do
      Snakepit.PythonPackages.ensure!({:list, requirements}, quiet: true)
    end

    :ok
  end

  defp ensure_python_runtime! do
    python_config = Application.get_env(:snakepit, :python, [])

    if Keyword.get(python_config, :managed, false) do
      version = Keyword.get(python_config, :python_version, "3.12")
      Snakepit.PythonRuntime.install_managed(version, [])
    end

    :ok
  end

  defp verify_environment!(config) do
    requirements = derive_requirements(config.libraries)

    case Snakepit.PythonPackages.check_installed(requirements) do
      {:ok, :all_installed} ->
        :ok

      {:ok, {:missing, missing}} ->
        raise SnakeBridge.EnvironmentError,
          message: "Missing Python packages: #{inspect(missing)}",
          suggestion: "Run: mix snakebridge.setup"
    end
  end

  defp library_to_requirement(lib) do
    package = lib.pypi_package || lib.python_name || to_string(lib.name)
    version = translate_version(lib.version)
    extras = lib.extras || []

    base = if extras != [] do
      "#{package}[#{Enum.join(extras, ",")}]"
    else
      package
    end

    if version do
      "#{base}#{version}"
    else
      base
    end
  end

  defp translate_version(nil), do: nil
  defp translate_version(:stdlib), do: nil
  defp translate_version(v) when is_binary(v) do
    # Already PEP-440 format
    if String.starts_with?(v, ["~=", ">=", "<=", "==", "!="]) do
      v
    else
      # Assume Elixir-style ~> X.Y
      case Regex.run(~r/^~>\s*(.+)$/, v) do
        [_, ver] -> "~=#{ver}"
        nil -> "==#{v}"
      end
    end
  end
end
```

### Config Extension

Add to `lib/snakebridge/config.ex`:

```elixir
defmodule Config.Library do
  defstruct [
    :name,
    :version,
    :module_name,
    :python_name,
    :pypi_package,      # NEW
    :extras,            # NEW
    :include,
    :exclude,
    :streaming,
    :submodules
  ]
end
```

---

## Phase 3: Strict Mode Enforcement

**Owner**: SnakeBridge
**Effort**: 0.5 days

### Modify: `lib/mix/tasks/compile/snakebridge.ex`

```elixir
defmodule Mix.Tasks.Compile.Snakebridge do
  # ... existing code ...

  def run(_args) do
    config = Config.load()

    # Check strict mode FIRST
    if strict_mode?(config) do
      run_strict(config)
    else
      run_normal(config)
    end
  end

  defp strict_mode?(config) do
    System.get_env("SNAKEBRIDGE_STRICT") == "1" ||
      config.strict == true
  end

  defp run_strict(config) do
    manifest = Manifest.load(config.metadata_dir)
    detected = Scanner.scan(config.scan_paths, config)
    missing = Manifest.missing(manifest, detected)

    if missing != [] do
      formatted = format_missing(missing)

      Mix.raise("""
      SnakeBridge strict mode: #{length(missing)} symbol(s) not in manifest.

      Missing:
      #{formatted}

      To fix:
        1. Run `mix snakebridge.setup` locally
        2. Commit the updated manifest and generated files
        3. Re-run CI

      Set SNAKEBRIDGE_STRICT=0 to disable strict mode.
      """)
    end

    # In strict mode, we still compile generated files but never regenerate
    :ok
  end

  defp run_normal(config) do
    # Ensure environment first
    SnakeBridge.PythonEnv.ensure!(config)

    # ... existing introspection and generation logic ...
  end

  defp format_missing(missing) do
    missing
    |> Enum.take(10)
    |> Enum.map(fn {mod, fun, arity} ->
      "  - #{mod}.#{fun}/#{arity}"
    end)
    |> Enum.join("\n")
    |> Kernel.<>(if length(missing) > 10, do: "\n  ... and #{length(missing) - 10} more", else: "")
  end
end
```

---

## Phase 4: Lockfile Extension

**Owner**: SnakeBridge
**Effort**: 1 day

### Modify: `lib/snakebridge/lock.ex`

```elixir
defmodule SnakeBridge.Lock do
  # ... existing code ...

  @doc """
  Builds the lock file content with full environment identity.
  """
  def build(config) do
    {:ok, python, meta} = Snakepit.PythonRuntime.resolve_executable()

    requirements = SnakeBridge.PythonEnv.derive_requirements(config.libraries)
    package_metadata = get_package_metadata(requirements)

    %{
      "version" => @version,
      "environment" => %{
        "snakebridge_version" => snakebridge_version(),
        "generator_hash" => generator_hash(),
        "python_version" => meta.python_version,
        "python_platform" => meta.python_platform,
        "python_runtime_hash" => meta.python_runtime_hash,
        "python_packages_hash" => compute_packages_hash(package_metadata),
        "elixir_version" => System.version(),
        "otp_version" => otp_version()
      },
      "libraries" => build_libraries(config.libraries),
      "python_packages" => package_metadata  # NEW
    }
  end

  defp get_package_metadata(requirements) do
    case Snakepit.PythonPackages.lock_metadata(requirements) do
      {:ok, metadata} -> metadata
      {:error, _} -> %{}
    end
  end

  defp compute_packages_hash(metadata) do
    # Sort for determinism
    sorted = metadata
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Jason.encode!()

    :crypto.hash(:sha256, sorted) |> Base.encode16(case: :lower)
  end
end
```

### New Lock File Format

```json
{
  "version": "0.4.0",
  "environment": {
    "snakebridge_version": "0.4.0",
    "generator_hash": "c9163ff...",
    "python_version": "3.12.3",
    "python_platform": "x86_64-pc-linux-gnu",
    "python_runtime_hash": "1319c137...",
    "python_packages_hash": "a1b2c3d4...",
    "elixir_version": "1.18.4",
    "otp_version": "28"
  },
  "libraries": {
    "numpy": {"requested": "~=1.26", "resolved": "~=1.26", "hash": null}
  },
  "python_packages": {
    "numpy": {"version": "1.26.4", "hash": "sha256:abc123..."},
    "sympy": {"version": "1.12.1", "hash": "sha256:def456..."}
  }
}
```

---

## Phase 5: Mix Task

**Owner**: SnakeBridge
**Effort**: 0.5 days

### New File: `lib/mix/tasks/snakebridge.setup.ex`

```elixir
defmodule Mix.Tasks.Snakebridge.Setup do
  @moduledoc """
  Provisions the Python environment for SnakeBridge introspection.

  ## Usage

      mix snakebridge.setup

  This task:
  1. Installs managed Python if configured (via Snakepit)
  2. Installs required Python packages
  3. Verifies the environment is ready for introspection

  ## Options

      --upgrade    Upgrade packages to latest matching versions
      --verbose    Show detailed output
      --check      Only check, don't install (exit 1 if missing)
  """

  use Mix.Task

  @shortdoc "Provision Python environment for SnakeBridge"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      switches: [upgrade: :boolean, verbose: :boolean, check: :boolean]
    )

    Mix.Task.run("loadpaths")

    config = SnakeBridge.Config.load()
    requirements = SnakeBridge.PythonEnv.derive_requirements(config.libraries)

    if requirements == [] do
      Mix.shell().info("No Python packages required (all stdlib)")
      :ok
    else
      if opts[:check] do
        run_check(requirements)
      else
        run_install(requirements, opts)
      end
    end
  end

  defp run_check(requirements) do
    case Snakepit.PythonPackages.check_installed(requirements) do
      {:ok, :all_installed} ->
        Mix.shell().info("All packages installed")

      {:ok, {:missing, missing}} ->
        Mix.shell().error("Missing packages: #{inspect(missing)}")
        exit({:shutdown, 1})
    end
  end

  defp run_install(requirements, opts) do
    Mix.shell().info("Installing Python packages...")

    install_opts = [
      upgrade: opts[:upgrade] || false,
      quiet: !opts[:verbose]
    ]

    Snakepit.PythonPackages.ensure!({:list, requirements}, install_opts)

    Mix.shell().info("Done. #{length(requirements)} package(s) ready.")
  end
end
```

---

## Phase 6: Introspection Error Classification

**Owner**: SnakeBridge
**Effort**: 0.5 days

### New File: `lib/snakebridge/introspection_error.ex`

```elixir
defmodule SnakeBridge.IntrospectionError do
  @moduledoc """
  Structured error for introspection failures.
  """

  defexception [:type, :package, :message, :python_error, :suggestion]

  @type t :: %__MODULE__{
    type: :package_not_found | :import_error | :timeout | :introspection_bug,
    package: String.t() | nil,
    message: String.t(),
    python_error: String.t() | nil,
    suggestion: String.t() | nil
  }

  def message(%{type: type, package: pkg, message: msg, suggestion: sug}) do
    base = case type do
      :package_not_found ->
        "Package '#{pkg}' not found"
      :import_error ->
        "Import error for '#{pkg}': #{msg}"
      :timeout ->
        "Introspection timed out: #{msg}"
      :introspection_bug ->
        "Introspection script error: #{msg}"
    end

    if sug, do: "#{base}\n\nSuggestion: #{sug}", else: base
  end

  @doc """
  Parses Python stderr to classify the error.
  """
  def from_python_output(output, package) do
    cond do
      String.contains?(output, "ModuleNotFoundError") ->
        %__MODULE__{
          type: :package_not_found,
          package: package,
          message: "Package not installed",
          python_error: output,
          suggestion: "Run: mix snakebridge.setup"
        }

      String.contains?(output, "ImportError") ->
        %__MODULE__{
          type: :import_error,
          package: package,
          message: extract_import_error(output),
          python_error: output,
          suggestion: "Check library dependencies (e.g., CUDA for torch)"
        }

      true ->
        %__MODULE__{
          type: :introspection_bug,
          package: package,
          message: "Unexpected error during introspection",
          python_error: output,
          suggestion: "Please report this issue"
        }
    end
  end

  defp extract_import_error(output) do
    case Regex.run(~r/ImportError: (.+)$/m, output) do
      [_, msg] -> String.trim(msg)
      nil -> "Unknown import error"
    end
  end
end
```

---

## Implementation Order

1. **Week 1**
   - Day 1-2: `Snakepit.PythonPackages` (Phase 1)
   - Day 3: `SnakeBridge.PythonEnv` (Phase 2)
   - Day 4: Strict mode (Phase 3)
   - Day 5: Tests and integration

2. **Week 2**
   - Day 1: Lockfile extension (Phase 4)
   - Day 2: Mix task (Phase 5)
   - Day 3: Error classification (Phase 6)
   - Day 4-5: End-to-end testing, docs

## Testing Strategy

### Unit Tests

- `Snakepit.PythonPackages` - mock System.cmd, test install logic
- `SnakeBridge.PythonEnv` - mock PythonPackages, test derivation
- `SnakeBridge.Lock` - test new format, hash stability

### Integration Tests

- Fresh project with libraries → `mix snakebridge.setup` → `mix compile`
- Strict mode with missing symbol → compile fails
- Lock file matches installed packages

### CI Matrix

- Ubuntu + managed Python (UV)
- macOS + system Python (pip)
- Windows + managed Python (UV)

## Rollout

1. Release `snakepit` with `PythonPackages` first
2. Release `snakebridge` depending on new snakepit version
3. Update documentation with new workflow
4. Add migration guide for existing projects
