defmodule SnakeBridge.Manifest do
  @moduledoc """
  Manifest storage for generated symbols.
  """

  @spec load(SnakeBridge.Config.t()) :: map()
  def load(config) do
    path = manifest_path(config)

    case File.read(path) do
      {:ok, content} ->
        Jason.decode!(content)

      {:error, :enoent} ->
        %{"version" => version(), "symbols" => %{}, "classes" => %{}}
    end
  end

  @spec save(SnakeBridge.Config.t(), map()) :: :ok
  def save(config, manifest) do
    path = manifest_path(config)
    File.mkdir_p!(Path.dirname(path))

    manifest
    |> sort_manifest()
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(path, &1))
  end

  @spec missing(map(), list({module(), atom(), non_neg_integer()})) ::
          list({module(), atom(), non_neg_integer()})
  def missing(manifest, detected) do
    existing = MapSet.new(Map.keys(manifest["symbols"] || %{}))

    class_modules =
      manifest
      |> Map.get("classes", %{})
      |> Map.values()
      |> Enum.map(& &1["module"])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    detected
    |> Enum.reject(fn {mod, func, arity} ->
      MapSet.member?(existing, symbol_key({mod, func, arity})) or
        MapSet.member?(class_modules, module_to_string(mod))
    end)
  end

  @spec put_symbols(map(), list({String.t(), map()})) :: map()
  def put_symbols(manifest, entries) do
    symbols =
      manifest
      |> Map.get("symbols", %{})
      |> Map.merge(Map.new(entries))

    Map.put(manifest, "symbols", symbols)
  end

  @spec put_classes(map(), list({String.t(), map()})) :: map()
  def put_classes(manifest, entries) do
    classes =
      manifest
      |> Map.get("classes", %{})
      |> Map.merge(Map.new(entries))

    Map.put(manifest, "classes", classes)
  end

  @spec symbol_key({module(), atom(), non_neg_integer()}) :: String.t()
  def symbol_key({module, function, arity}) do
    "#{module}.#{function}/#{arity}"
  end

  @spec class_key(module()) :: String.t()
  def class_key(module) when is_atom(module) do
    Module.split(module) |> Enum.join(".")
  end

  defp module_to_string(module) when is_atom(module) do
    Module.split(module) |> Enum.join(".")
  end

  defp manifest_path(config) do
    Path.join(config.metadata_dir, "manifest.json")
  end

  defp version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end

  defp sort_manifest(manifest) do
    manifest
    |> update_in(["symbols"], fn symbols ->
      symbols
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Map.new()
    end)
    |> update_in(["classes"], fn classes ->
      classes
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Map.new()
    end)
  end
end
