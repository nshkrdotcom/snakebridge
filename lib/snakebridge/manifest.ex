defmodule SnakeBridge.Manifest do
  @moduledoc """
  Parse simplified manifests into SnakeBridge.Config structs.

  Manifests are curated, stateless function lists for Python libraries.
  """

  alias SnakeBridge.{Config, Generator}
  alias SnakeBridge.Manifest.Reader

  @type manifest :: map()

  @doc """
  Load a manifest file and return a SnakeBridge.Config.

  Supports either a manifest map or a %SnakeBridge.Config{} in the file.
  """
  @spec from_file(String.t()) :: {:ok, Config.t()} | {:error, term()}
  def from_file(path) when is_binary(path) do
    case Reader.read_file(path) do
      {:ok, %Config{} = config} ->
        {:ok, config}

      {:ok, data} when is_map(data) ->
        {:ok, to_config(data)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Convert a manifest map to SnakeBridge.Config.
  """
  @spec to_config(manifest()) :: Config.t()
  def to_config(manifest) when is_map(manifest) do
    %Config{
      python_module: get_manifest_field(manifest, :python_module),
      version: get_manifest_field(manifest, :version),
      description: get_manifest_field(manifest, :description),
      introspection: %{enabled: false},
      classes: [],
      functions: build_config_functions(manifest)
    }
  end

  defp build_config_functions(manifest) do
    elixir_module = parse_elixir_module(manifest)
    types = get_manifest_field(manifest, :types) || %{}
    functions = get_manifest_field(manifest, :functions) || []
    normalize_functions(functions, manifest, types, elixir_module)
  end

  defp parse_elixir_module(manifest) do
    elixir_module = get_manifest_field(manifest, :elixir_module)

    cond do
      is_atom(elixir_module) -> elixir_module
      is_binary(elixir_module) -> module_from_string(elixir_module)
      true -> nil
    end
  end

  defp get_manifest_field(manifest, field) do
    Map.get(manifest, field) || Map.get(manifest, Atom.to_string(field))
  end

  @doc """
  Validate a manifest file.
  """
  @spec validate_file(String.t()) :: {:ok, Config.t()} | {:error, [String.t()]}
  def validate_file(path) when is_binary(path) do
    with {:ok, config} <- from_file(path),
         {:ok, validated} <- validate(config) do
      {:ok, validated}
    else
      {:error, reason} -> {:error, format_errors(reason, path)}
    end
  end

  @doc """
  Validate a manifest map or config.
  """
  @spec validate(manifest() | Config.t()) :: {:ok, Config.t()} | {:error, [String.t()]}
  def validate(%Config{} = config) do
    base_errors =
      case Config.validate(config) do
        {:ok, _} -> []
        {:error, errors} -> errors
      end

    function_errors =
      config.functions
      |> Enum.with_index()
      |> Enum.flat_map(fn {func, idx} ->
        validate_function(func, idx)
      end)

    errors = base_errors ++ function_errors

    if Enum.empty?(errors), do: {:ok, config}, else: {:error, errors}
  end

  def validate(manifest) when is_map(manifest) do
    manifest
    |> to_config()
    |> validate()
  rescue
    e -> {:error, [Exception.message(e)]}
  end

  @doc """
  Convert a manifest map into formatted Elixir code.
  """
  @spec to_elixir_code(manifest()) :: String.t()
  def to_elixir_code(manifest) when is_map(manifest) do
    manifest
    |> inspect(pretty: true, limit: :infinity)
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  @doc """
  Convert a manifest map into formatted JSON.
  """
  @spec to_json(manifest()) :: String.t()
  def to_json(manifest) when is_map(manifest) do
    Jason.encode!(manifest, pretty: true)
  end

  @doc """
  Generate and load modules from a manifest map.
  """
  @spec generate_from_manifest(map()) :: {:ok, [module()]} | {:error, term()}
  def generate_from_manifest(manifest) when is_map(manifest) do
    manifest
    |> to_config()
    |> Generator.generate_all()
  end

  defp normalize_functions(functions, manifest, types, elixir_module)
       when is_list(functions) do
    Enum.map(functions, fn
      {name, opts} when is_list(opts) ->
        normalize_function(Map.new(opts), name, manifest, types, elixir_module)

      {name, opts} when is_map(opts) ->
        normalize_function(opts, name, manifest, types, elixir_module)

      %{} = opts ->
        normalize_function(opts, nil, manifest, types, elixir_module)

      other ->
        raise ArgumentError, "Invalid function entry in manifest: #{inspect(other)}"
    end)
  end

  defp normalize_function(opts, tuple_name, manifest, types, elixir_module) do
    python_name = extract_python_name(opts, tuple_name)
    elixir_name = extract_elixir_name(opts, tuple_name, python_name)
    python_path = extract_python_path(opts, manifest, python_name)
    return_type = extract_return_type(opts)
    docstring = extract_docstring(opts)
    streaming = extract_streaming(opts)
    streaming_tool = extract_streaming_tool(opts)
    parameters = extract_parameters(opts, types)

    %{}
    |> maybe_put(:name, python_name)
    |> maybe_put(:python_path, python_path)
    |> maybe_put(:elixir_name, elixir_name)
    |> maybe_put(:docstring, docstring)
    |> maybe_put(:parameters, parameters)
    |> maybe_put(:return_type, return_type)
    |> maybe_put(:streaming, streaming)
    |> maybe_put(:streaming_tool, streaming_tool)
    |> maybe_put(:elixir_module, elixir_module)
  end

  defp extract_python_name(opts, tuple_name) do
    opts
    |> Map.get(:python_name) || Map.get(opts, "python_name") ||
      Map.get(opts, :name) || Map.get(opts, "name") ||
      tuple_name
      |> normalize_name()
  end

  defp extract_elixir_name(opts, tuple_name, python_name) do
    raw_elixir_name = Map.get(opts, :elixir_name) || Map.get(opts, "elixir_name") || tuple_name
    normalize_elixir_name(raw_elixir_name, python_name)
  end

  defp extract_python_path(opts, manifest, python_name) do
    Map.get(opts, :python_path) || Map.get(opts, "python_path") ||
      default_python_path(manifest, python_name)
  end

  defp extract_return_type(opts) do
    (Map.get(opts, :returns) || Map.get(opts, "returns"))
    |> normalize_type()
  end

  defp extract_docstring(opts) do
    Map.get(opts, :doc) || Map.get(opts, "doc") || Map.get(opts, :docstring) ||
      Map.get(opts, "docstring")
  end

  defp extract_streaming(opts) do
    Map.get(opts, :streaming) || Map.get(opts, "streaming") || false
  end

  defp extract_streaming_tool(opts) do
    Map.get(opts, :streaming_tool) || Map.get(opts, "streaming_tool") ||
      Map.get(opts, :stream_tool) || Map.get(opts, "stream_tool")
  end

  defp extract_parameters(opts, types) do
    args = Map.get(opts, :args) || Map.get(opts, "args") || []
    build_parameters(args, types)
  end

  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name
  defp normalize_name(nil), do: nil

  defp normalize_elixir_name(nil, python_name) when is_binary(python_name) do
    Generator.Helpers.normalize_function_name(python_name, nil)
  end

  defp normalize_elixir_name(name, _python_name) when is_atom(name), do: name
  defp normalize_elixir_name(name, _python_name) when is_binary(name), do: String.to_atom(name)

  defp default_python_path(manifest, python_name) do
    prefix =
      Map.get(manifest, :python_path_prefix) ||
        Map.get(manifest, "python_path_prefix") ||
        Map.get(manifest, :python_module) ||
        Map.get(manifest, "python_module")

    case {prefix, python_name} do
      {p, n} when is_binary(p) and is_binary(n) -> "#{p}.#{n}"
      _ -> nil
    end
  end

  defp build_parameters(args, types) when is_list(args) and is_map(types) do
    Enum.map(args, fn arg ->
      name = normalize_name(arg)
      type = Map.get(types, arg) || Map.get(types, name)

      %{
        name: name,
        type: normalize_type(type),
        required: true,
        kind: "keyword"
      }
    end)
  end

  defp build_parameters(_, _), do: []

  defp normalize_type(nil), do: nil
  defp normalize_type(:term), do: %{type: "any"}
  defp normalize_type(:any), do: %{type: "any"}
  defp normalize_type(:string), do: %{type: "str"}
  defp normalize_type(:integer), do: %{type: "int"}
  defp normalize_type(:float), do: %{type: "float"}
  defp normalize_type(:boolean), do: %{type: "bool"}
  defp normalize_type(:map), do: %{type: "dict", key_type: "str", value_type: "any"}
  defp normalize_type(:list), do: %{type: "list", element_type: "any"}
  defp normalize_type("map"), do: %{type: "dict", key_type: "str", value_type: "any"}
  defp normalize_type("list"), do: %{type: "list", element_type: "any"}

  defp normalize_type({:list, element}) do
    %{type: "list", element_type: normalize_type(element) || "any"}
  end

  defp normalize_type({:map, key, value}) do
    %{
      type: "dict",
      key_type: normalize_type(key) || "str",
      value_type: normalize_type(value) || "any"
    }
  end

  defp normalize_type({:union, types}) when is_list(types) do
    %{type: "union", union_types: Enum.map(types, &normalize_type/1)}
  end

  defp normalize_type(type) when is_binary(type), do: %{type: type}
  defp normalize_type(type) when is_map(type), do: type

  defp module_from_string(module_name) when is_binary(module_name) do
    module_name
    |> String.trim_leading("Elixir.")
    |> String.split(".")
    |> Module.concat()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validate_function(func, idx) do
    errors = []

    errors =
      if Map.get(func, :name) || Map.get(func, "name") do
        errors
      else
        ["functions[#{idx}] missing name" | errors]
      end

    errors =
      if Map.get(func, :python_path) || Map.get(func, "python_path") do
        errors
      else
        ["functions[#{idx}] missing python_path" | errors]
      end

    errors
  end

  defp format_errors({:invalid_manifest, path}, _input) do
    ["Invalid manifest (expected map or %SnakeBridge.Config{}): #{path}"]
  end

  defp format_errors(%RuntimeError{} = error, _input), do: [Exception.message(error)]
  defp format_errors(errors, _input) when is_list(errors), do: errors
  defp format_errors(other, path), do: ["#{path}: #{inspect(other)}"]

  @doc """
  Determine which Python module should be introspected for a manifest/config.

  Prefers the common python_path prefix in functions when it differs from
  config.python_module (e.g., wrapper modules under snakebridge_adapter).
  """
  @spec introspection_module(Config.t()) :: String.t() | nil
  def introspection_module(%Config{} = config) do
    prefixes =
      config.functions
      |> Enum.map(fn func -> Map.get(func, :python_path) || Map.get(func, "python_path") end)
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&python_prefix/1)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    case prefixes do
      [prefix] -> prefix
      _ -> config.python_module
    end
  end

  defp python_prefix(path) when is_binary(path) do
    parts = String.split(path, ".")

    case Enum.drop(parts, -1) do
      [] -> nil
      prefix_parts -> Enum.join(prefix_parts, ".")
    end
  end
end
