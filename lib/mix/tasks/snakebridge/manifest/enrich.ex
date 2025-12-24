defmodule Mix.Tasks.Snakebridge.Manifest.Enrich do
  @moduledoc """
  Enrich manifest files with docstrings and type hints from introspection.

  ## Usage

      mix snakebridge.manifest.enrich sympy
      mix snakebridge.manifest.enrich priv/snakebridge/manifests/sympy.json --depth 2
      mix snakebridge.manifest.enrich sympy --cache --cache-dir priv/snakebridge/schemas
      mix snakebridge.manifest.enrich sympy --schema priv/snakebridge/schemas/sympy.json
  """

  use Mix.Task

  @shortdoc "Enrich manifests with Python docstrings/types"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest
  alias SnakeBridge.Manifest.Loader
  alias SnakeBridge.Manifest.Reader
  alias SnakeBridge.SnakepitLauncher

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          depth: :integer,
          output: :string,
          schema: :string,
          cache: :boolean,
          cache_dir: :string
        ],
        aliases: [
          d: :depth,
          o: :output
        ]
      )

    depth = Keyword.get(opts, :depth, 1)
    output_path = Keyword.get(opts, :output)
    schema_path = Keyword.get(opts, :schema)
    cache? = Keyword.get(opts, :cache, false)
    cache_dir = Path.expand(Keyword.get(opts, :cache_dir, "priv/snakebridge/schemas"))

    if positional == [] do
      Mix.raise("Expected manifest name or path.")
    end

    if output_path && length(positional) > 1 do
      Mix.raise("--output can only be used with a single manifest.")
    end

    if schema_path && length(positional) > 1 do
      Mix.raise("--schema can only be used with a single manifest.")
    end

    Enum.each(positional, fn target ->
      path = resolve_manifest_path(target)
      manifest = load_manifest_map!(path)
      python_module = Map.get(manifest, :python_module) || Map.get(manifest, "python_module")

      schema =
        load_schema!(schema_path, python_module,
          depth: depth,
          cache?: cache?,
          cache_dir: cache_dir
        )

      updated = enrich_manifest(manifest, schema)
      write_path = output_path || path

      File.write!(write_path, Manifest.to_json(updated))
      Mix.shell().info("✓ Enriched manifest written to: #{write_path}")
    end)
  end

  defp resolve_manifest_path(target) do
    cond do
      File.exists?(target) ->
        target

      String.ends_with?(target, ".json") or String.ends_with?(target, ".exs") ->
        Mix.raise("Manifest file not found: #{target}")

      true ->
        name = String.to_atom(target)

        case Loader.manifest_path(name) do
          nil -> Mix.raise("Unknown manifest: #{target}")
          path -> path
        end
    end
  end

  defp load_manifest_map!(path) do
    manifest = Reader.read_file!(path)

    case manifest do
      %SnakeBridge.Config{} ->
        Mix.raise("Manifest must be a map (not a %SnakeBridge.Config{}): #{path}")

      %{} ->
        manifest
    end
  end

  defp load_schema!(schema_path, python_module, opts) do
    depth = Keyword.get(opts, :depth, 1)
    cache? = Keyword.get(opts, :cache?, false)
    cache_dir = Keyword.get(opts, :cache_dir, "priv/snakebridge/schemas")

    cond do
      schema_path ->
        read_schema_file!(schema_path)

      cache? ->
        if is_nil(python_module) do
          Mix.raise("Manifest missing python_module; cannot use --cache")
        end

        cache_path = Path.join(cache_dir, cache_filename(python_module))

        if File.exists?(cache_path) do
          read_schema_file!(cache_path)
        else
          SnakepitLauncher.ensure_pool_started!()
          {:ok, schema} = SnakeBridge.Discovery.discover(python_module, depth: depth)
          File.mkdir_p!(cache_dir)
          File.write!(cache_path, Jason.encode!(schema, pretty: true) <> "\n")
          schema
        end

      true ->
        SnakepitLauncher.ensure_pool_started!()
        {:ok, schema} = SnakeBridge.Discovery.discover(python_module, depth: depth)
        schema
    end
  end

  defp cache_filename(python_module) when is_binary(python_module) do
    python_module
    |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")
    |> String.replace(".", "_")
    |> Kernel.<>(".json")
  end

  defp read_schema_file!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  rescue
    e -> Mix.raise("Failed to read schema #{path}: #{Exception.message(e)}")
  end

  defp enrich_manifest(manifest, schema) do
    functions_key = if Map.has_key?(manifest, "functions"), do: "functions", else: :functions
    types_key = if Map.has_key?(manifest, "types"), do: "types", else: :types

    functions = Map.get(manifest, functions_key) || []
    types = Map.get(manifest, types_key) || %{}
    key_mode = types_key_mode(types, types_key)

    functions_map = Map.get(schema, "functions", %{})

    {updated_functions, updated_types} =
      Enum.map_reduce(functions, types, fn entry, acc_types ->
        name = function_name_from_entry(entry)

        schema_func =
          if is_nil(name) do
            nil
          else
            Map.get(functions_map, name) || Map.get(functions_map, to_string(name))
          end

        normalized = normalize_schema_function(schema_func)

        {updated_entry, next_types} = enrich_entry(entry, normalized, acc_types, key_mode)
        {updated_entry, next_types}
      end)

    manifest
    |> Map.put(functions_key, updated_functions)
    |> Map.put(types_key, updated_types)
  end

  defp normalize_schema_function(nil) do
    %{docstring: nil, return_type: nil, parameters: []}
  end

  defp normalize_schema_function(schema) do
    %{
      docstring: Map.get(schema, "docstring") || Map.get(schema, :docstring),
      return_type: Map.get(schema, "return_type") || Map.get(schema, :return_type),
      parameters:
        normalize_schema_params(Map.get(schema, "parameters") || Map.get(schema, :parameters))
    }
  end

  defp normalize_schema_params(params) when is_list(params) do
    params
    |> Enum.map(fn param ->
      %{
        name: Map.get(param, "name") || Map.get(param, :name),
        type: Map.get(param, "type") || Map.get(param, :type)
      }
    end)
    |> Enum.reject(fn %{name: name} -> is_nil(name) end)
  end

  defp normalize_schema_params(_), do: []

  defp enrich_entry(entry, schema_func, types, key_mode) do
    docstring = schema_func.docstring
    return_type = schema_func.return_type
    params = schema_func.parameters

    args =
      params
      |> Enum.map(& &1.name)
      |> Enum.reject(&is_nil/1)
      |> normalize_args(key_mode)

    updated_types = merge_types(types, params, key_mode)
    updated_entry = apply_updates(entry, docstring, return_type, args)

    {updated_entry, updated_types}
  end

  defp merge_types(types, params, key_mode) do
    Enum.reduce(params, types, fn %{name: name, type: type}, acc ->
      cond do
        is_nil(name) or is_nil(type) ->
          acc

        has_type?(acc, name) ->
          acc

        true ->
          Map.put(acc, type_key(name, key_mode), type)
      end
    end)
  end

  defp normalize_args(args, :atom) do
    Enum.map(args, fn
      name when is_atom(name) -> name
      name when is_binary(name) -> String.to_atom(name)
      name -> name
    end)
  end

  defp normalize_args(args, :string) do
    Enum.map(args, &to_string/1)
  end

  defp has_type?(types, name) do
    name_str = to_string(name)

    Enum.any?(Map.keys(types), fn key ->
      to_string(key) == name_str
    end)
  end

  defp type_key(name, :atom) when is_atom(name), do: name
  defp type_key(name, :atom) when is_binary(name), do: String.to_atom(name)
  defp type_key(name, :atom), do: name
  defp type_key(name, :string), do: to_string(name)

  defp types_key_mode(types, types_key) do
    cond do
      Enum.any?(Map.keys(types), &is_atom/1) -> :atom
      types_key == :types -> :atom
      true -> :string
    end
  end

  defp apply_updates({name, opts}, docstring, return_type, args) when is_list(opts) do
    opts = maybe_put_doc_kw(opts, docstring)
    opts = maybe_put_args_kw(opts, args)
    opts = maybe_put_returns_kw(opts, return_type)
    {name, opts}
  end

  defp apply_updates({name, opts}, docstring, return_type, args) when is_map(opts) do
    opts = maybe_put_doc_map(opts, docstring)
    opts = maybe_put_args_map(opts, args)
    opts = maybe_put_returns_map(opts, return_type)
    {name, opts}
  end

  defp apply_updates(%{} = opts, docstring, return_type, args) do
    opts
    |> maybe_put_doc_map(docstring)
    |> maybe_put_args_map(args)
    |> maybe_put_returns_map(return_type)
  end

  defp maybe_put_doc_kw(opts, nil), do: opts
  defp maybe_put_doc_kw(opts, ""), do: opts

  defp maybe_put_doc_kw(opts, docstring) do
    if Keyword.has_key?(opts, :doc) or Keyword.has_key?(opts, :docstring) do
      opts
    else
      Keyword.put(opts, :doc, docstring)
    end
  end

  defp maybe_put_args_kw(opts, []), do: opts

  defp maybe_put_args_kw(opts, args) do
    if Keyword.has_key?(opts, :args) do
      opts
    else
      Keyword.put(opts, :args, args)
    end
  end

  defp maybe_put_returns_kw(opts, nil), do: opts
  defp maybe_put_returns_kw(opts, ""), do: opts

  defp maybe_put_returns_kw(opts, return_type) do
    if Keyword.has_key?(opts, :returns) or Keyword.has_key?(opts, :return) do
      opts
    else
      Keyword.put(opts, :returns, return_type)
    end
  end

  defp maybe_put_doc_map(opts, nil), do: opts
  defp maybe_put_doc_map(opts, ""), do: opts

  defp maybe_put_doc_map(opts, docstring) do
    if Map.has_key?(opts, :doc) or Map.has_key?(opts, :docstring) or
         Map.has_key?(opts, "doc") or Map.has_key?(opts, "docstring") do
      opts
    else
      Map.put(opts, :doc, docstring)
    end
  end

  defp maybe_put_args_map(opts, []), do: opts

  defp maybe_put_args_map(opts, args) do
    if Map.has_key?(opts, :args) or Map.has_key?(opts, "args") do
      opts
    else
      Map.put(opts, :args, args)
    end
  end

  defp maybe_put_returns_map(opts, nil), do: opts
  defp maybe_put_returns_map(opts, ""), do: opts

  defp maybe_put_returns_map(opts, return_type) do
    if Map.has_key?(opts, :returns) or Map.has_key?(opts, "returns") or
         Map.has_key?(opts, :return) or Map.has_key?(opts, "return") do
      opts
    else
      Map.put(opts, :returns, return_type)
    end
  end

  defp function_name_from_entry({name, _opts}) when is_atom(name), do: Atom.to_string(name)
  defp function_name_from_entry({name, _opts}) when is_binary(name), do: name

  defp function_name_from_entry(%{} = opts) do
    cond do
      Map.has_key?(opts, :python_name) -> Map.get(opts, :python_name)
      Map.has_key?(opts, "python_name") -> Map.get(opts, "python_name")
      Map.has_key?(opts, :name) -> normalize_name(Map.get(opts, :name))
      Map.has_key?(opts, "name") -> normalize_name(Map.get(opts, "name"))
      Map.has_key?(opts, :python_path) -> last_segment(Map.get(opts, :python_path))
      Map.has_key?(opts, "python_path") -> last_segment(Map.get(opts, "python_path"))
      true -> nil
    end
  end

  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name
  defp normalize_name(_), do: nil

  defp last_segment(nil), do: nil

  defp last_segment(path) when is_binary(path) do
    path |> String.split(".") |> List.last()
  end
end
