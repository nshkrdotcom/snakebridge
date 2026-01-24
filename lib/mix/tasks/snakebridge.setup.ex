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
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [upgrade: :boolean, verbose: :boolean, check: :boolean]
      )

    Mix.Task.run("loadconfig")

    config = SnakeBridge.Config.load()
    SnakeBridge.PythonEnv.sync_project_requirements!(config)
    requirements = SnakeBridge.PythonEnv.derive_requirements(config.libraries)

    if requirements == [] do
      Mix.shell().info("No Python packages required (all stdlib)")
      ensure_python_runtime!()
      install_snakebridge_requirements(opts)
      :ok
    else
      if opts[:check] do
        run_check(requirements)
      else
        ensure_python_runtime!()
        install_snakebridge_requirements(opts)
        run_install(requirements, opts)
      end
    end
  end

  defp run_check(requirements) do
    case python_packages_module().check_installed(requirements, python_packages_opts([])) do
      {:ok, :all_installed} ->
        Mix.shell().info("All packages installed")

      {:ok, {:missing, missing}} ->
        Mix.raise("Missing packages: #{inspect(missing)}")
    end
  end

  defp run_install(requirements, opts) do
    Mix.shell().info("Installing Python packages...")

    install_opts = [
      upgrade: opts[:upgrade] || false,
      quiet: !opts[:verbose]
    ]

    python_packages_module().ensure!({:list, requirements}, python_packages_opts(install_opts))
    Mix.shell().info("Done. #{length(requirements)} package(s) ready.")
  end

  defp install_snakebridge_requirements(opts) do
    case snakebridge_requirements_path() do
      nil ->
        :ok

      path ->
        install_opts = [upgrade: opts[:upgrade] || false, quiet: !opts[:verbose]]
        python_packages_module().ensure!({:file, path}, python_packages_opts(install_opts))
    end
  end

  defp ensure_python_runtime! do
    python_config = Application.get_env(:snakepit, :python, [])

    if Keyword.get(python_config, :managed, false) do
      python_runtime_module().install_managed(SnakeBridge.PythonRuntimeRunner, [])
    end

    :ok
  end

  defp python_packages_module do
    Application.get_env(:snakebridge, :python_packages, Snakepit.PythonPackages)
  end

  defp python_packages_opts(opts) do
    if python_packages_module() == Snakepit.PythonPackages do
      Keyword.put_new(opts, :runner, SnakeBridge.PythonPackagesRunner)
    else
      opts
    end
  end

  defp python_runtime_module do
    Application.get_env(:snakebridge, :python_runtime, Snakepit.PythonRuntime)
  end

  defp snakebridge_requirements_path do
    case :code.priv_dir(:snakebridge) do
      {:error, _} ->
        nil

      priv_dir ->
        path = Path.join([to_string(priv_dir), "python", "requirements.txt"])
        if File.exists?(path), do: path, else: nil
    end
  end
end
