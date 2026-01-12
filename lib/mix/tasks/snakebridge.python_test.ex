defmodule Mix.Tasks.Snakebridge.PythonTest do
  @shortdoc "Bootstrap and run SnakeBridge Python tests"
  @moduledoc """
  Bootstraps the SnakeBridge Python environment and runs the Python test suite.

  Usage:

      mix snakebridge.python_test
      mix snakebridge.python_test -- --maxfail=1

  Options:
    * `--no-setup` - Skip `mix snakebridge.setup`
    * `--no-pytest-install` - Skip ensuring pytest is installed
  """

  use Mix.Task

  @pytest_requirements ["pytest>=7.0", "pytest-asyncio>=0.23"]

  @impl true
  def run(args) do
    {opts, pytest_args, _} =
      OptionParser.parse(args,
        strict: [no_setup: :boolean, no_pytest_install: :boolean]
      )

    Mix.Task.run("loadconfig")

    unless opts[:no_setup] do
      Mix.Task.run("snakebridge.setup")
    end

    unless opts[:no_pytest_install] do
      ensure_pytest!()
    end

    {python, env, project_root} = resolve_python_env()

    tests = [
      Path.join(project_root, "priv/python/test_snakebridge_adapter.py"),
      Path.join(project_root, "priv/python/test_bridge_client_streaming.py"),
      Path.join(project_root, "priv/python/test_snakebridge_types.py")
    ]

    cmd_args = ["-m", "pytest"] ++ tests ++ pytest_args

    {output, status} =
      System.cmd(python, cmd_args,
        env: env,
        cd: project_root,
        stderr_to_stdout: true
      )

    if output != "" do
      Mix.shell().info(output)
    end

    if status != 0 do
      Mix.raise("Python tests failed with exit code #{status}")
    end
  end

  defp ensure_pytest! do
    python_packages_module().ensure!(
      {:list, @pytest_requirements},
      python_packages_opts(quiet: true)
    )
  end

  defp resolve_python_env do
    project_root = File.cwd!()
    priv_python = Path.join(project_root, "priv/python")
    venv_python = Path.join(project_root, ".venv/bin/python")

    python =
      System.get_env("SNAKEBRIDGE_TEST_PYTHON") ||
        if(File.exists?(venv_python), do: venv_python, else: nil) ||
        Snakepit.PythonRuntime.executable_path() ||
        System.find_executable("python3") ||
        System.find_executable("python") ||
        Mix.raise(
          "Python executable not found; run mix snakebridge.setup or set SNAKEBRIDGE_TEST_PYTHON"
        )

    env = [{"PYTHONPATH", priv_python}]

    {python, env, project_root}
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
end
