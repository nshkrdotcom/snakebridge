defmodule Mix.Tasks.Snakebridge.Verify do
  @moduledoc """
  Verifies the lock file against the current hardware environment.

  This task checks that the hardware environment where the lock file was created
  is compatible with the current system. It detects:

  - Platform mismatches (OS, architecture)
  - CUDA version differences
  - Missing GPU capabilities
  - CPU feature mismatches

  ## Usage

      mix snakebridge.verify           # Verify with warnings
      mix snakebridge.verify --strict  # Fail on any mismatch
      mix snakebridge.verify --verbose # Show detailed info

  ## Options

  - `--strict` - Treat warnings as errors and fail
  - `--verbose` - Print detailed hardware information
  - `--file PATH` - Use a specific lock file (default: snakebridge.lock)

  ## Exit Codes

  - 0 - Compatible environment
  - 1 - Incompatible environment (or warnings in strict mode)

  ## Examples

      # Standard verification
      $ mix snakebridge.verify
      ✓ Lock file compatible with current environment

      # Strict mode (CI)
      $ mix snakebridge.verify --strict
      ✗ CUDA version mismatch: lock has 12.1, current has 11.8

      # Verbose output
      $ mix snakebridge.verify --verbose
      Current hardware:
        Platform: linux-x86_64
        Accelerator: cuda
        CUDA version: 12.1
        GPU count: 2

      Lock file:
        Platform: linux-x86_64
        Accelerator: cuda
        CUDA version: 12.1
        GPU count: 2

      ✓ Lock file compatible

  """

  use Mix.Task

  alias SnakeBridge.Lock.Verifier

  @shortdoc "Verify lock file compatibility with current hardware"

  @switches [
    strict: :boolean,
    verbose: :boolean,
    file: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _remaining, _invalid} = OptionParser.parse(args, switches: @switches)

    lock_file = Keyword.get(opts, :file, "snakebridge.lock")
    strict? = Keyword.get(opts, :strict, false)
    verbose? = Keyword.get(opts, :verbose, false)

    case load_lock(lock_file) do
      {:ok, lock} ->
        if verbose?, do: print_verbose_info(lock)
        verify_and_report(lock, strict?)

      {:error, :not_found} ->
        Mix.shell().error("Lock file not found: #{lock_file}")
        Mix.shell().error("Run `mix compile` to generate the lock file.")
        raise Mix.Error, message: "Lock file not found"

      {:error, reason} ->
        Mix.shell().error("Failed to load lock file: #{inspect(reason)}")
        raise Mix.Error, message: "Failed to load lock file"
    end
  end

  defp load_lock(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok, Jason.decode!(content)}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_and_report(lock, strict?) do
    case Verifier.verify(lock) do
      :ok ->
        Mix.shell().info("✓ Lock file compatible with current environment")
        :ok

      {:warning, warnings} ->
        Enum.each(warnings, fn warning ->
          Mix.shell().info("⚠ Warning: #{warning}")
        end)

        if strict? do
          Mix.shell().error("Strict mode: treating warnings as errors")
          raise Mix.Error, message: "Lock file has compatibility warnings"
        else
          Mix.shell().info("✓ Lock file compatible (with warnings)")
          :ok
        end

      {:error, errors} ->
        Enum.each(errors, fn error ->
          Mix.shell().error("✗ Error: #{error}")
        end)

        raise Mix.Error, message: "Lock file incompatible with current environment"
    end
  end

  defp print_verbose_info(lock) do
    current = hardware_module().identity()
    current_caps = hardware_module().capabilities()

    Mix.shell().info("Current hardware:")
    Mix.shell().info("  Platform: #{current["platform"]}")
    Mix.shell().info("  Accelerator: #{current["accelerator"]}")

    if current_caps.cuda do
      Mix.shell().info("  CUDA version: #{current_caps.cuda_version}")
    end

    if current_caps.mps do
      Mix.shell().info("  MPS: available")
    end

    Mix.shell().info("  GPU count: #{current["gpu_count"]}")
    Mix.shell().info("  CPU features: #{Enum.join(current["cpu_features"] || [], ", ")}")
    Mix.shell().info("")

    lock_env = Map.get(lock, "environment", %{})
    lock_hardware = Map.get(lock_env, "hardware", %{})
    lock_platform = Map.get(lock_env, "platform", %{})

    Mix.shell().info("Lock file:")
    Mix.shell().info("  Platform: #{lock_platform["os"]}-#{lock_platform["arch"]}")
    Mix.shell().info("  Accelerator: #{lock_hardware["accelerator"]}")

    if cuda_version = lock_hardware["cuda_version"] do
      Mix.shell().info("  CUDA version: #{cuda_version}")
    end

    Mix.shell().info("  GPU count: #{lock_hardware["gpu_count"]}")

    cpu_features = lock_hardware["cpu_features"] || []
    Mix.shell().info("  CPU features: #{Enum.join(cpu_features, ", ")}")
    Mix.shell().info("")
  end

  defp hardware_module do
    Application.get_env(:snakebridge, :hardware_module, Snakepit.Hardware)
  end
end
