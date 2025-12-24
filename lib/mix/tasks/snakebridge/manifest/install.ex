defmodule Mix.Tasks.Snakebridge.Manifest.Install do
  @moduledoc """
  Install Python packages referenced by SnakeBridge manifests.

  ## Usage

      mix snakebridge.manifest.install [--venv PATH] [--python PATH] [--load sympy,pylatexenc]
  """

  use Mix.Task

  @shortdoc "Install Python packages for configured manifests"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest.Loader
  alias SnakeBridge.Manifest.Reader
  alias SnakeBridge.Python

  @impl Mix.Task
  def run(args) do
    {opts, _positional, _} =
      OptionParser.parse(args,
        strict: [
          venv: :string,
          python: :string,
          load: :string,
          all: :boolean,
          include_core: :boolean
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

    {python_exec, pip_exec} = Python.ensure_venv(base_python, venv_path)

    Python.run!(python_exec, ["-m", "ensurepip", "--upgrade"])
    Python.run!(python_exec, ["-m", "pip", "install", "--upgrade", "pip"])

    include_core? = Keyword.get(opts, :include_core, false)

    if include_core? do
      snakepit_reqs = Application.app_dir(:snakepit, "priv/python/requirements.txt")
      Python.install_requirements(pip_exec, snakepit_reqs)
      Python.run!(pip_exec, ["install", "-e", Path.expand("priv/python")])
    end

    load_setting = load_setting_from_opts(opts)
    custom_paths = Application.get_env(:snakebridge, :custom_manifests, [])
    {files, errors} = Loader.resolve_manifest_files(load_setting, custom_paths)

    if errors != [] do
      Mix.shell().error("Unknown manifests: #{inspect(errors)}")
    end

    packages =
      files
      |> Enum.map(&manifest_package_spec/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if packages == [] do
      Mix.shell().info("No manifest packages found to install.")
      return()
    end

    Mix.shell().info("Installing manifest packages:")
    Enum.each(packages, &Mix.shell().info("  - #{&1}"))

    Python.install_packages(pip_exec, packages)

    Mix.shell().info("✓ Manifest package installation complete.")
  end

  defp load_setting_from_opts(opts) do
    cond do
      Keyword.get(opts, :all, false) ->
        :all

      load = Keyword.get(opts, :load) ->
        load
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)

      true ->
        Application.get_env(:snakebridge, :load, [])
    end
  end

  defp manifest_package_spec(path) do
    manifest = Reader.read_file!(path)
    index = Loader.index()

    {package, version} = extract_package_info(manifest, index)
    build_package_spec(package, version)
  rescue
    _ -> nil
  end

  defp extract_package_info(%SnakeBridge.Config{} = config, _index) do
    {config.python_module, config.version}
  end

  defp extract_package_info(%{} = data, index) do
    package = extract_package_name(data, index)
    version = Map.get(data, :version) || Map.get(data, "version")
    {package, version}
  end

  defp extract_package_name(data, index) do
    Map.get(data, :pypi_package) || Map.get(data, "pypi_package") ||
      lookup_package_in_index(data, index) ||
      Map.get(data, :python_module) || Map.get(data, "python_module")
  end

  defp lookup_package_in_index(data, index) do
    name = Map.get(data, :name) || Map.get(data, "name")
    get_in(index, [to_string(name || ""), "pypi_package"])
  end

  defp build_package_spec(nil, _version), do: nil

  defp build_package_spec(package, nil), do: package

  defp build_package_spec(package, version) when is_binary(version) do
    version = String.trim(version)

    cond do
      String.starts_with?(version, "~>") ->
        package <> version_to_pip(version)

      String.starts_with?(version, ">=") or String.starts_with?(version, "==") or
          String.starts_with?(version, "<") ->
        package <> version

      true ->
        package <> "==" <> version
    end
  end

  defp version_to_pip("~>" <> rest) do
    rest = String.trim(rest)
    segments = rest |> String.split(".") |> Enum.map(&String.to_integer/1)

    case segments do
      [major, minor, patch] ->
        ">=#{major}.#{minor}.#{patch},<#{major}.#{minor + 1}.0"

      [major, minor] ->
        ">=#{major}.#{minor},<#{major + 1}.0"

      [major] ->
        ">=#{major},<#{major + 1}.0"

      _ ->
        ">=#{rest}"
    end
    |> then(&"#{&1}")
  end

  defp return, do: nil
end
