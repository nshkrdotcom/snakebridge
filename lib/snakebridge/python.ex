defmodule SnakeBridge.Python do
  @moduledoc """
  Helpers for managing Python environments and packages.

  Provides zero-friction Python environment management - venvs are created
  automatically, packages are installed on demand, no manual setup required.
  """

  require Logger

  @default_venv ".venv"

  @doc """
  Ensures a complete Python environment is ready for SnakeBridge.

  Creates venv if needed, installs core dependencies, returns paths.
  This is called automatically - users never need to run setup manually.
  """
  @spec ensure_environment!(keyword()) :: {python :: String.t(), pip :: String.t()}
  def ensure_environment!(opts \\ []) do
    venv_path = Keyword.get(opts, :venv, @default_venv) |> Path.expand()
    quiet? = Keyword.get(opts, :quiet, false)

    {python, pip} = ensure_venv_exists!(venv_path, quiet?)
    ensure_core_deps!(python, quiet?)

    {python, pip}
  end

  @doc """
  Ensures a venv exists, creating it if necessary.
  """
  @spec ensure_venv(String.t(), String.t()) :: {String.t(), String.t()}
  def ensure_venv(base_python, venv_path) do
    venv_python = Path.join(venv_path, "bin/python3")
    venv_pip = Path.join(venv_path, "bin/pip")

    unless File.exists?(venv_python) do
      run!(base_python, ["-m", "venv", venv_path])
    end

    {venv_python, venv_pip}
  end

  @doc """
  Installs a Python package, silently skipping if already installed.
  """
  @spec ensure_package!(String.t(), String.t(), keyword()) :: :ok
  def ensure_package!(python, package, opts \\ []) do
    quiet? = Keyword.get(opts, :quiet, false)

    # Check if already installed
    case System.cmd(python, ["-c", "import #{package_import_name(package)}"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, _} ->
        unless quiet?, do: Logger.info("Installing Python package: #{package}")
        run!(python, ["-m", "pip", "install", "--quiet", package])
        :ok
    end
  end

  @doc """
  Installs multiple packages.
  """
  @spec install_packages(String.t(), [String.t()]) :: :ok
  def install_packages(_pip_exec, []), do: :ok

  def install_packages(pip_exec, packages) when is_list(packages) do
    run!(pip_exec, ["install" | packages])
    :ok
  end

  @spec install_requirements(String.t(), String.t()) :: :ok
  def install_requirements(pip_exec, requirements_path) do
    if File.exists?(requirements_path) do
      run!(pip_exec, ["install", "-r", requirements_path])
    end

    :ok
  end

  @spec run!(String.t(), [String.t()], keyword()) :: String.t()
  def run!(cmd, args, opts \\ []) do
    {output, code} = System.cmd(cmd, args, Keyword.merge([stderr_to_stdout: true], opts))

    if code != 0 do
      raise "Command failed: #{cmd} #{Enum.join(args, " ")}\n#{output}"
    end

    output
  end

  @doc """
  Returns the default venv path.
  """
  @spec default_venv() :: String.t()
  def default_venv, do: @default_venv

  @doc """
  Returns the python executable path for the default venv.
  """
  @spec default_python() :: String.t()
  def default_python, do: Path.join([@default_venv, "bin", "python3"]) |> Path.expand()

  @doc """
  Returns the pip executable path for the default venv.
  """
  @spec default_pip() :: String.t()
  def default_pip, do: Path.join([@default_venv, "bin", "pip"]) |> Path.expand()

  # Private helpers

  defp ensure_venv_exists!(venv_path, quiet?) do
    venv_python = Path.join(venv_path, "bin/python3")
    venv_pip = Path.join(venv_path, "bin/pip")

    unless File.exists?(venv_python) do
      unless quiet?, do: Logger.info("Creating Python venv at #{venv_path}...")

      base_python = find_base_python!()
      run!(base_python, ["-m", "venv", venv_path])

      unless quiet?, do: Logger.info("Venv created successfully")
    end

    {venv_python, venv_pip}
  end

  defp ensure_core_deps!(python, quiet?) do
    # Ensure pip is up to date
    run!(python, ["-m", "ensurepip", "--upgrade"], stderr_to_stdout: true)
    run!(python, ["-m", "pip", "install", "--upgrade", "--quiet", "pip"])

    # Install snakepit requirements
    snakepit_reqs = Application.app_dir(:snakepit, "priv/python/requirements.txt")

    if File.exists?(snakepit_reqs) do
      unless quiet?, do: Logger.debug("Installing Snakepit requirements...")
      run!(python, ["-m", "pip", "install", "--quiet", "-r", snakepit_reqs])
    end

    # Install snakebridge adapter
    adapter_dir = resolve_adapter_dir()

    if adapter_dir && File.exists?(Path.join(adapter_dir, "setup.py")) do
      unless quiet?, do: Logger.debug("Installing SnakeBridge adapter...")
      run!(python, ["-m", "pip", "install", "--quiet", "-e", adapter_dir])
    end

    :ok
  end

  defp find_base_python! do
    cond do
      python = System.get_env("SNAKEPIT_PYTHON") -> python
      python = System.find_executable("python3") -> python
      python = System.find_executable("python") -> python
      true -> raise "Python not found. Please install Python 3.8+ and ensure it's in PATH."
    end
  end

  defp resolve_adapter_dir do
    local = Path.expand("priv/python")
    app_dir = Application.app_dir(:snakebridge, "priv/python")

    cond do
      File.exists?(local) -> local
      File.exists?(app_dir) -> app_dir
      true -> nil
    end
  end

  # Extract importable name from package spec (e.g., "chardet>=5.0" -> "chardet")
  defp package_import_name(package) do
    package
    |> String.split(~r/[<>=!~]/, parts: 2)
    |> List.first()
    |> String.replace("-", "_")
  end
end
