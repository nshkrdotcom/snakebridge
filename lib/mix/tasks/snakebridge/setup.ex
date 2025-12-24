defmodule Mix.Tasks.Snakebridge.Setup do
  @moduledoc """
  Set up a Python virtual environment and install Snakepit + SnakeBridge deps.

  ## Usage

      mix snakebridge.setup [--venv PATH] [--python PATH]
  """

  use Mix.Task

  @shortdoc "Setup Python venv and install SnakeBridge dependencies"

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _positional, _} =
      OptionParser.parse(args,
        strict: [
          venv: :string,
          python: :string
        ],
        aliases: [
          v: :venv,
          p: :python
        ]
      )

    venv_path = Path.expand(Keyword.get(opts, :venv, ".venv"))

    base_python =
      Keyword.get(opts, :python) || System.get_env("SNAKEPIT_PYTHON") ||
        System.find_executable("python3")

    unless base_python do
      Mix.raise("Python executable not found. Pass --python or set SNAKEPIT_PYTHON.")
    end

    Mix.shell().info("Creating virtual environment at #{venv_path}...")
    {venv_python, venv_pip} = SnakeBridge.Python.ensure_venv(base_python, venv_path)

    Mix.shell().info("Installing Python dependencies...")
    SnakeBridge.Python.run!(venv_python, ["-m", "ensurepip", "--upgrade"])
    SnakeBridge.Python.run!(venv_python, ["-m", "pip", "install", "--upgrade", "pip"])

    snakepit_reqs = Application.app_dir(:snakepit, "priv/python/requirements.txt")
    snakebridge_reqs = Path.expand("priv/python/requirements.snakebridge.txt")

    SnakeBridge.Python.install_requirements(venv_pip, snakepit_reqs)

    if File.exists?(snakebridge_reqs) do
      SnakeBridge.Python.install_requirements(venv_pip, snakebridge_reqs)
    end

    SnakeBridge.Python.run!(venv_pip, ["install", "-e", Path.expand("priv/python")])

    snakebridge_python = Path.expand("priv/python")
    snakepit_python = Application.app_dir(:snakepit, "priv/python")

    Mix.shell().info("")
    Mix.shell().info("Setup complete.")
    Mix.shell().info("Export these for runtime:")
    Mix.shell().info("  export SNAKEPIT_PYTHON=#{venv_python}")
    Mix.shell().info("  export PYTHONPATH=#{snakebridge_python}:#{snakepit_python}:$PYTHONPATH")
  end
end
