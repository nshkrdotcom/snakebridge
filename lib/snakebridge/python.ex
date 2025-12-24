defmodule SnakeBridge.Python do
  @moduledoc """
  Helpers for managing Python environments and packages.
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

  @spec install_requirements(String.t(), String.t()) :: :ok
  def install_requirements(pip_exec, requirements_path) do
    if File.exists?(requirements_path) do
      run!(pip_exec, ["install", "-r", requirements_path])
    end

    :ok
  end

  @spec install_packages(String.t(), [String.t()]) :: :ok
  def install_packages(_pip_exec, []), do: :ok

  def install_packages(pip_exec, packages) when is_list(packages) do
    run!(pip_exec, ["install" | packages])
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
end
