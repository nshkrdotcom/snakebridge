defmodule SnakeBridge.Manifest.Registry do
  @moduledoc """
  Registry of manifest-allowed Python calls.

  Stores allowlisted module/function pairs and class paths for runtime enforcement.
  """

  @key {__MODULE__, :allowlist}

  @type allowlist :: %{
          functions: MapSet.t({String.t(), String.t()}),
          classes: MapSet.t(String.t())
        }

  @spec reset() :: :ok
  def reset do
    :persistent_term.put(@key, %{functions: MapSet.new(), classes: MapSet.new()})
    :ok
  end

  @spec register_configs([SnakeBridge.Config.t()]) :: :ok
  def register_configs(configs) when is_list(configs) do
    reset()

    Enum.each(configs, &register_config/1)
  end

  @spec register_config(SnakeBridge.Config.t()) :: :ok
  def register_config(%SnakeBridge.Config{} = config) do
    allowlist = current_allowlist()

    function_keys =
      config.functions
      |> Enum.map(&function_key(&1, config))
      |> Enum.reject(&is_nil/1)

    class_keys =
      config.classes
      |> Enum.map(&get_field(&1, :python_path))
      |> Enum.filter(&is_binary/1)

    updated = %{
      functions: Enum.reduce(function_keys, allowlist.functions, &MapSet.put(&2, &1)),
      classes: Enum.reduce(class_keys, allowlist.classes, &MapSet.put(&2, &1))
    }

    :persistent_term.put(@key, updated)
    :ok
  end

  @spec allowed_function?(String.t(), String.t()) :: boolean()
  def allowed_function?(module_path, function_name)
      when is_binary(module_path) and is_binary(function_name) do
    allowlist = current_allowlist()
    MapSet.member?(allowlist.functions, {module_path, function_name})
  end

  @spec allowed_class?(String.t()) :: boolean()
  def allowed_class?(python_path) when is_binary(python_path) do
    allowlist = current_allowlist()
    MapSet.member?(allowlist.classes, python_path)
  end

  defp current_allowlist do
    :persistent_term.get(@key, %{functions: MapSet.new(), classes: MapSet.new()})
  end

  defp function_key(func, config) when is_map(func) do
    name = get_field(func, :name)
    python_path = get_field(func, :python_path)

    module_path =
      cond do
        is_binary(python_path) -> module_path_from_python_path(python_path)
        is_binary(config.python_module) and is_binary(name) -> config.python_module
        true -> nil
      end

    if is_binary(module_path) and is_binary(name) do
      {module_path, name}
    else
      nil
    end
  end

  defp module_path_from_python_path(python_path) when is_binary(python_path) do
    case String.split(python_path, ".") do
      [single] -> single
      parts -> Enum.take(parts, length(parts) - 1) |> Enum.join(".")
    end
  end

  defp get_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
