defmodule Mix.Tasks.Snakebridge.Manifest.Gen do
  @moduledoc """
  Generate a draft manifest from introspection.

  ## Usage

      mix snakebridge.manifest.gen MODULE [OPTIONS]

  ## Options

    * `--output` - Output path for the manifest
    * `--depth` - Discovery depth (default: 1)
    * `--limit` - Limit number of functions
    * `--prefix` - Python path prefix for functions
    * `--elixir-module` - Elixir module name (e.g. SnakeBridge.SymPy)
    * `--category` - Category atom (e.g. math, text)
    * `--version` - Version string
  """

  use Mix.Task

  @shortdoc "Generate a draft manifest from introspection"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest
  alias SnakeBridge.SnakepitLauncher
  alias SnakeBridge.TypeSystem.Mapper

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          depth: :integer,
          limit: :integer,
          prefix: :string,
          elixir_module: :string,
          category: :string,
          version: :string
        ],
        aliases: [
          o: :output,
          d: :depth,
          l: :limit,
          p: :prefix,
          m: :elixir_module
        ]
      )

    module_name =
      case positional do
        [name | _] -> name
        [] -> nil
      end

    if module_name == nil do
      Mix.raise("Expected module name as first argument.")
    end

    depth = Keyword.get(opts, :depth, 1)

    output_path =
      Keyword.get(opts, :output) ||
        "priv/snakebridge/manifests/_drafts/#{module_name}.json"

    prefix = Keyword.get(opts, :prefix, module_name)
    limit = Keyword.get(opts, :limit)
    category = Keyword.get(opts, :category)
    version = Keyword.get(opts, :version)

    elixir_module =
      case Keyword.get(opts, :elixir_module) do
        nil -> "SnakeBridge.#{default_module_name(module_name)}"
        module_str -> module_str
      end

    Mix.shell().info("Discovering Python library: #{module_name}")

    SnakepitLauncher.ensure_pool_started!()

    case SnakeBridge.Discovery.discover(module_name, depth: depth) do
      {:ok, schema} ->
        {functions, types} = build_functions(schema, limit)

        manifest =
          %{}
          |> maybe_put("name", module_name)
          |> maybe_put("python_module", module_name)
          |> maybe_put("python_path_prefix", prefix)
          |> maybe_put("version", version)
          |> maybe_put("category", category)
          |> maybe_put("elixir_module", elixir_module)
          |> maybe_put("types", types)
          |> maybe_put("functions", functions)

        output_path
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(output_path, Manifest.to_json(manifest))

        Mix.shell().info("✓ Manifest written to: #{output_path}")

      {:error, reason} ->
        Mix.raise("Failed to discover module '#{module_name}': #{inspect(reason)}")
    end
  end

  defp build_functions(schema, limit) do
    functions_map = Map.get(schema, "functions", %{})

    functions =
      functions_map
      |> Enum.map(fn {_name, desc} -> build_function_entry(desc) end)
      |> Enum.sort_by(fn entry -> Map.get(entry, "name") || "" end)
      |> maybe_limit(limit)

    types =
      functions_map
      |> Enum.flat_map(fn {_name, desc} ->
        params = Map.get(desc, "parameters", []) || []

        Enum.map(params, fn param ->
          name = Map.get(param, "name") || Map.get(param, :name)
          type = Map.get(param, "type") || Map.get(param, :type) || "any"
          {name, type}
        end)
      end)
      |> Enum.reject(fn {name, _} -> is_nil(name) end)
      |> Enum.into(%{})

    {functions, types}
  end

  defp build_function_entry(desc) do
    name = Map.get(desc, "name") || Map.get(desc, :name)
    docstring = Map.get(desc, "docstring") || Map.get(desc, :docstring)
    return_type = Map.get(desc, "return_type") || Map.get(desc, :return_type) || :term

    args =
      desc
      |> Map.get("parameters", [])
      |> Enum.map(fn param -> Map.get(param, "name") || Map.get(param, :name) end)
      |> Enum.reject(fn param -> param in [nil, "self", "cls"] end)

    %{}
    |> maybe_put("name", name)
    |> maybe_put("args", args)
    |> maybe_put("returns", return_type)
    |> maybe_put("doc", docstring)
  end

  defp maybe_limit(list, nil), do: list
  defp maybe_limit(list, limit) when is_integer(limit) and limit > 0, do: Enum.take(list, limit)
  defp maybe_limit(list, _), do: list

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp default_module_name(module_name) do
    module_name
    |> Mapper.python_class_to_elixir_module()
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end
end
