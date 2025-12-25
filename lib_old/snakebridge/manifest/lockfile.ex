defmodule SnakeBridge.Manifest.Lockfile do
  @moduledoc """
  Generate and read manifest lockfiles with pinned Python package versions.
  """

  alias SnakeBridge.Manifest.Loader
  alias SnakeBridge.Manifest.Reader
  alias SnakeBridge.Python

  @default_path "priv/snakebridge/manifest.lock.json"

  @type entry :: %{
          name: String.t(),
          package: String.t(),
          python_module: String.t() | nil,
          requirement: String.t() | nil,
          manifest_path: String.t()
        }

  @spec default_path() :: String.t()
  def default_path do
    Path.expand(@default_path)
  end

  @spec generate([String.t()], String.t()) :: {:ok, map(), [String.t()]} | {:error, term()}
  def generate(manifest_paths, python_exec) do
    index = Loader.index()
    index_by_file = index_file_map(index)

    {entries, warnings} =
      manifest_paths
      |> Enum.map(&manifest_entry(&1, index, index_by_file))
      |> Enum.split_with(&match?({:ok, _}, &1))
      |> then(fn {oks, errs} ->
        {
          Enum.map(oks, fn {:ok, entry} -> entry end),
          Enum.map(errs, fn {:error, msg} -> msg end)
        }
      end)

    if entries == [] do
      {:error, :no_manifests}
    else
      packages =
        entries
        |> Enum.map(& &1.package)
        |> Enum.uniq()

      case fetch_versions(python_exec, packages) do
        {:ok, versions} ->
          lock = build_lock(entries, versions, python_exec)
          {:ok, lock, warnings}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec write(map(), String.t()) :: :ok
  def write(lock, path) when is_binary(path) do
    encoded = Jason.encode!(lock, pretty: true)
    File.write!(path, encoded <> "\n")
    :ok
  end

  @spec read(String.t()) :: {:ok, map()} | {:error, term()}
  def read(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      {:ok, decoded}
    else
      error -> error
    end
  end

  defp index_file_map(index) do
    Enum.reduce(index, %{}, fn {name, entry}, acc ->
      file = Map.get(entry, :file) || Map.get(entry, "file")
      if file, do: Map.put(acc, file, name), else: acc
    end)
  end

  defp manifest_entry(path, index, index_by_file) do
    manifest = Reader.read_file!(path)

    case manifest do
      %SnakeBridge.Config{} = config ->
        process_config_manifest(path, config, index, index_by_file)

      %{} = data ->
        process_map_manifest(path, data, index, index_by_file)
    end
  rescue
    e -> {:error, "Failed to read manifest #{path}: #{Exception.message(e)}"}
  end

  defp process_config_manifest(path, config, index, index_by_file) do
    name = manifest_name_from_index(path, index_by_file) || Path.rootname(Path.basename(path))
    python_module = config.python_module
    requirement = config.version

    package =
      index
      |> Map.get(String.to_atom(name), %{})
      |> Map.get(:pypi_package) || python_module

    build_entry(path, name, package, python_module, requirement)
  end

  defp process_map_manifest(path, data, index, index_by_file) do
    name = extract_manifest_name(path, data, index_by_file)
    python_module = Map.get(data, :python_module) || Map.get(data, "python_module")
    requirement = Map.get(data, :version) || Map.get(data, "version")
    package = extract_package_name(data, name, index, python_module)

    build_entry(path, name, package, python_module, requirement)
  end

  defp extract_manifest_name(path, data, index_by_file) do
    Map.get(data, :name) || Map.get(data, "name") ||
      manifest_name_from_index(path, index_by_file) || Path.rootname(Path.basename(path))
  end

  defp extract_package_name(data, name, index, python_module) do
    Map.get(data, :pypi_package) || Map.get(data, "pypi_package") ||
      index
      |> Map.get(to_name_atom(name), %{})
      |> Map.get(:pypi_package) || python_module
  end

  defp build_entry(_path, _name, nil, _python_module, _requirement),
    do: {:error, "Manifest missing pypi package or python_module"}

  defp build_entry(path, name, package, python_module, requirement) do
    {:ok,
     %{
       name: normalize_name(name),
       package: package,
       python_module: python_module,
       requirement: requirement,
       manifest_path: Path.relative_to_cwd(path)
     }}
  end

  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name
  defp normalize_name(name), do: to_string(name)

  defp to_name_atom(name) when is_atom(name), do: name
  defp to_name_atom(name) when is_binary(name), do: String.to_atom(name)
  defp to_name_atom(name), do: name

  defp manifest_name_from_index(path, index_by_file) do
    file = Path.basename(path)

    case Map.get(index_by_file, file) do
      nil -> nil
      name when is_atom(name) -> Atom.to_string(name)
      name -> name
    end
  end

  defp fetch_versions(_python_exec, []), do: {:ok, %{}}

  defp fetch_versions(python_exec, packages) do
    payload = Jason.encode!(packages)

    script =
      """
      import json
      import sys
      try:
          from importlib import metadata
      except Exception:
          import importlib_metadata as metadata

      packages = json.loads(sys.argv[1])
      results = {}
      missing = []
      for pkg in packages:
          try:
              results[pkg] = metadata.version(pkg)
          except Exception:
              results[pkg] = None
              missing.append(pkg)

      print(json.dumps({"results": results, "missing": missing}))
      """

    output = Python.run!(python_exec, ["-c", script, payload])

    case Jason.decode(output) do
      {:ok, %{"results" => results, "missing" => []}} ->
        {:ok, results}

      {:ok, %{"results" => results, "missing" => missing}} ->
        {:error, {:missing_packages, missing, results}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_lock(entries, versions, python_exec) do
    %{
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "python_executable" => python_exec,
      "manifests" =>
        entries
        |> Enum.sort_by(& &1.name)
        |> Enum.reduce(%{}, fn entry, acc ->
          version = Map.get(versions, entry.package)

          Map.put(acc, entry.name, %{
            "package" => entry.package,
            "version" => version,
            "python_module" => entry.python_module,
            "requirement" => entry.requirement,
            "manifest_path" => entry.manifest_path
          })
        end)
    }
  end
end
