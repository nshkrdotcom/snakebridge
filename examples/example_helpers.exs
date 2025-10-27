# Example Helper System for SnakeBridge
# Automatically manages Python dependencies for examples

defmodule SnakeBridgeExample do
  @moduledoc """
  Helper module for SnakeBridge examples.

  Handles:
  - Automatic Python dependency installation
  - Snakepit configuration
  - Environment setup
  - Error reporting

  Usage in examples:
      SnakeBridgeExample.setup(
        python_packages: ["numpy"],
        description: "NumPy mathematical operations"
      )
  """

  def setup(opts \\ []) do
    packages = Keyword.get(opts, :python_packages, [])
    description = Keyword.get(opts, :description, "SnakeBridge Example")
    adapter = Keyword.get(opts, :adapter, "snakebridge_adapter.adapter.SnakeBridgeAdapter")

    IO.puts("\n🐍 #{description}\n")
    IO.puts(String.duplicate("=", 60))

    # Step 1: Configure Snakepit before it starts (Mix.install may start it)
    configure_snakepit(adapter)

    # Step 2: Install Elixir dependencies (makes Snakepit available)
    install_elixir_deps()

    # Step 3: Setup environment now that Snakepit is loaded
    python = setup_environment()

    # Step 4: Check and install Python packages
    if length(packages) > 0 do
      ensure_python_packages(python, packages)
    end

    # Step 5: Re-assert Snakepit config (in case install started it early)
    configure_snakepit(adapter)

    # Step 6: Configure SnakeBridge
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    IO.puts("\n✓ Environment ready\n")
  end

  defp setup_environment do
    project_root = File.cwd!()

    # Set PYTHONPATH
    snakebridge_python = Path.join([project_root, "priv", "python"])
    snakepit_python = Application.app_dir(:snakepit, "priv/python")

    pythonpath =
      [snakebridge_python, snakepit_python]
      |> Enum.filter(&File.dir?/1)
      |> Enum.join(":")

    System.put_env("PYTHONPATH", pythonpath)

    project_venv_python =
      Path.join([snakebridge_python, ".venv", "bin", "python3"])

    snakepit_repo_python =
      Path.expand("~/p/g/n/snakepit/.venv/bin/python3")

    python =
      resolve_python(System.get_env("SNAKEPIT_PYTHON")) ||
        resolve_python(project_venv_python) ||
        resolve_python(snakepit_repo_python) ||
        resolve_python("python3") ||
        "python3"

    System.put_env("SNAKEPIT_PYTHON", python)
    IO.puts("Using Python executable: #{python}")

    python
  end

  defp ensure_python_packages(python, packages) do
    for package <- packages do
      # Check if package is installed
      {_, status} =
        System.cmd(python, ["-c", "import #{package}"], stderr_to_stdout: true)

      if status != 0 do
        IO.puts("📦 Installing #{package}...")

        case System.cmd(python, ["-m", "pip", "install", package, "-q"]) do
          {_, 0} ->
            IO.puts("   ✓ #{package} installed")

          {output, _} ->
            IO.puts("   ✗ Failed to install #{package}")
            IO.puts(output)
            System.halt(1)
        end
      end
    end
  end

  defp configure_snakepit(adapter_spec) do
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
    Application.put_env(:snakepit, :pooling_enabled, true)

    Application.put_env(:snakepit, :pools, [
      %{
        name: :default,
        worker_profile: :process,
        pool_size: 2,
        adapter_module: Snakepit.Adapters.GRPCPython,
        adapter_args: ["--adapter", adapter_spec]
      }
    ])

    Application.put_env(:snakepit, :pool_config, %{pool_size: 2})
    Application.put_env(:snakepit, :grpc_port, 50051)
    Application.put_env(:snakepit, :log_level, :warning)
  end

  defp resolve_python(path) do
    case path do
      nil ->
        nil

      "" ->
        nil

      value ->
        expanded = Path.expand(value)

        cond do
          File.exists?(expanded) -> expanded
          exec = System.find_executable(value) -> exec
          true -> nil
        end
    end
  end

  defp install_elixir_deps do
    Mix.install([
      {:snakepit, "~> 0.6.4", override: true},
      {:snakebridge, path: "."},
      {:grpc, "~> 0.10.2"},
      {:protobuf, "~> 0.14.1"}
    ])

    IO.puts("Snakepit app dir after install: #{Application.app_dir(:snakepit)}")
  end

  def run(fun) when is_function(fun, 0) do
    # Use apply to defer module resolution to runtime
    apply(Snakepit, :run_as_script, [fn -> fun.() end])
  end
end
