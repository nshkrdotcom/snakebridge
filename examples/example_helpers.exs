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

    IO.puts("\n🐍 #{description}\n")
    IO.puts(String.duplicate("=", 60))

    # Step 1: Setup environment
    setup_environment()

    # Step 2: Check and install Python packages
    if length(packages) > 0 do
      ensure_python_packages(packages)
    end

    # Step 3: Configure Snakepit
    configure_snakepit()

    # Step 4: Install Elixir dependencies
    install_elixir_deps()

    # Step 5: Configure SnakeBridge
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    IO.puts("\n✓ Environment ready\n")
  end

  defp setup_environment do
    # Set PYTHONPATH
    snakebridge_python = Path.join([File.cwd!(), "priv", "python"])
    snakepit_python = Path.expand("deps/snakepit/priv/python")
    pythonpath = "#{snakebridge_python}:#{snakepit_python}"
    System.put_env("PYTHONPATH", pythonpath)

    # Use Snakepit venv if available
    snakepit_venv = Path.expand("~/p/g/n/snakepit/.venv/bin/python3")

    if File.exists?(snakepit_venv) do
      System.put_env("SNAKEPIT_PYTHON", snakepit_venv)
      {:ok, snakepit_venv}
    else
      # Fall back to system python3
      System.put_env("SNAKEPIT_PYTHON", "python3")
      {:ok, "python3"}
    end
  end

  defp ensure_python_packages(packages) do
    python = System.get_env("SNAKEPIT_PYTHON", "python3")

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

  defp configure_snakepit do
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
    Application.put_env(:snakepit, :pooling_enabled, true)

    Application.put_env(:snakepit, :pools, [
      %{
        name: :default,
        worker_profile: :process,
        pool_size: 2,
        adapter_module: Snakepit.Adapters.GRPCPython,
        adapter_args: ["--adapter", "snakebridge_adapter.adapter.SnakeBridgeAdapter"]
      }
    ])

    Application.put_env(:snakepit, :pool_config, %{pool_size: 2})
    Application.put_env(:snakepit, :grpc_port, 50051)
    Application.put_env(:snakepit, :log_level, :warning)
  end

  defp install_elixir_deps do
    Mix.install([
      {:snakepit, "~> 0.6"},
      {:snakebridge, path: "."},
      {:grpc, "~> 0.10.2"},
      {:protobuf, "~> 0.14.1"}
    ])
  end

  def run(fun) when is_function(fun, 0) do
    Snakepit.run_as_script(fn ->
      fun.()
    end)
  end
end
