defmodule SnakeBridge.Manifest.Loader do
  @moduledoc """
  Loads built-in and custom manifests and generates modules at runtime.
  """

  alias SnakeBridge.{Generator, Manifest}
  alias SnakeBridge.Manifest.{Reader, Registry}

  @doc """
  Load manifests based on application configuration.

  ## Config

  - `:load` - list of built-in manifest names or `:all`
  - `:custom_manifests` - list of file globs for user manifests
  """
  @spec load_configured() :: {:ok, [module()]} | {:error, list()}
  def load_configured do
    load_setting = Application.get_env(:snakebridge, :load, [])
    custom_paths = Application.get_env(:snakebridge, :custom_manifests, [])

    load(load_setting, custom_paths)
  end

  @doc """
  Resolve manifest file paths for the given load settings.
  """
  @spec resolve_manifest_files(:all | [atom()], list() | String.t()) ::
          {[String.t()], [term()]}
  def resolve_manifest_files(load_setting, custom_paths) do
    {builtin_files, builtin_errors} = resolve_builtin_files(load_setting)
    custom_files = resolve_custom_files(custom_paths)

    files =
      builtin_files
      |> Kernel.++(custom_files)
      |> Enum.uniq()

    {files, builtin_errors}
  end

  @doc """
  Load manifests by name and custom paths.
  """
  @spec load(:all | [atom()], list() | String.t()) :: {:ok, [module()]} | {:error, list()}
  def load(load_setting, custom_paths) do
    {files, builtin_errors} = resolve_manifest_files(load_setting, custom_paths)

    results = Enum.map(files, &load_file/1)

    modules =
      results
      |> Enum.flat_map(fn
        {:ok, %{modules: mods}} -> mods
        _ -> []
      end)

    configs =
      results
      |> Enum.flat_map(fn
        {:ok, %{config: config}} -> [config]
        _ -> []
      end)

    errors_from_load =
      results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.map(fn {:error, reason} -> reason end)

    errors = builtin_errors ++ errors_from_load

    report(load_setting, files, modules, errors)

    Registry.register_configs(configs)

    if Enum.empty?(errors) do
      {:ok, modules}
    else
      {:error, errors}
    end
  end

  @doc """
  Generate a simple manifest load report.
  """
  @spec report(:all | [atom()], [String.t()], [module()], list()) :: :ok
  def report(load_setting, files, modules, errors) do
    require Logger

    cond do
      load_setting in [nil, [], false] ->
        Logger.debug("SnakeBridge: no manifests configured to load")

      files == [] ->
        Logger.warning("SnakeBridge: manifest load configured, but no files resolved")

      true ->
        Logger.info("SnakeBridge: loaded manifests=#{length(files)} modules=#{length(modules)}")
        Logger.debug("SnakeBridge: generated modules=#{inspect(modules)}")
    end

    if errors != [] do
      Logger.error("SnakeBridge: manifest load errors=#{inspect(errors)}")
    end

    :ok
  end

  @doc """
  Return a health report for configured manifests.
  """
  @spec health() :: map()
  def health do
    load_setting = Application.get_env(:snakebridge, :load, [])
    custom_paths = Application.get_env(:snakebridge, :custom_manifests, [])
    {builtin_files, builtin_errors} = resolve_builtin_files(load_setting)
    custom_files = resolve_custom_files(custom_paths)

    %{
      load_setting: load_setting,
      builtin_files: builtin_files,
      custom_files: custom_files,
      builtin_errors: builtin_errors
    }
  end

  @doc """
  Return the built-in manifest index.
  """
  @spec index() :: map()
  def index do
    builtin_index()
  end

  @doc """
  Resolve a built-in manifest path by name.
  """
  @spec manifest_path(atom()) :: String.t() | nil
  def manifest_path(name) when is_atom(name) do
    index = builtin_index()

    cond do
      Map.has_key?(index, name) ->
        manifest_path_from_entry(Map.get(index, name))

      Map.has_key?(index, Atom.to_string(name)) ->
        manifest_path_from_entry(Map.get(index, Atom.to_string(name)))

      true ->
        nil
    end
  end

  defp load_file(path) do
    case Manifest.from_file(path) do
      {:ok, config} ->
        case Generator.generate_all(config) do
          {:ok, modules} -> {:ok, %{config: config, modules: modules}}
          {:error, _} = error -> error
        end

      {:error, reason} ->
        {:error, %{path: path, reason: reason}}
    end
  end

  defp resolve_builtin_files(:all) do
    index = builtin_index()
    {index |> Map.values() |> Enum.map(&manifest_path_from_entry/1), []}
  end

  defp resolve_builtin_files(names) when is_list(names) do
    index = builtin_index()

    Enum.reduce(names, {[], []}, fn name, {paths, errors} ->
      entry = Map.get(index, name) || Map.get(index, Atom.to_string(name))

      case entry do
        nil -> {paths, [{:unknown_manifest, name} | errors]}
        _ -> {[manifest_path_from_entry(entry) | paths], errors}
      end
    end)
    |> then(fn {paths, errors} -> {Enum.reverse(paths), Enum.reverse(errors)} end)
  end

  defp resolve_builtin_files(_), do: {[], []}

  defp resolve_custom_files(paths) when is_binary(paths), do: resolve_custom_files([paths])

  defp resolve_custom_files(paths) when is_list(paths) do
    paths
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&(String.ends_with?(&1, ".json") or String.ends_with?(&1, ".exs")))
    |> Enum.reject(&(String.ends_with?(&1, "_index.json") or String.ends_with?(&1, "_index.exs")))
  end

  defp resolve_custom_files(_), do: []

  defp builtin_index do
    index_path = Path.join(manifest_dir(), "_index.json")

    if File.exists?(index_path) do
      Reader.read_file!(index_path)
    else
      %{}
    end
  end

  defp manifest_path_from_entry(%{file: file}) when is_binary(file) do
    Path.join(manifest_dir(), file)
  end

  defp manifest_path_from_entry(%{"file" => file}) when is_binary(file) do
    Path.join(manifest_dir(), file)
  end

  defp manifest_dir do
    priv =
      case :code.priv_dir(:snakebridge) do
        {:error, _} -> "priv"
        path -> List.to_string(path)
      end

    Path.join(priv, "snakebridge/manifests")
  end
end
