defmodule SnakeBridge.Manifest.Agent do
  @moduledoc """
  Heuristic manifest suggester (non-autonomous).
  """

  alias SnakeBridge.Discovery

  @exclude_patterns [
    "read",
    "write",
    "save",
    "load",
    "open",
    "close",
    "file",
    "path",
    "dir",
    "mkdir",
    "rmdir",
    "http",
    "socket",
    "connect",
    "db",
    "sql",
    "plot",
    "show",
    "render",
    "gui",
    "stdin",
    "stdout",
    "stderr",
    "input",
    "print",
    "log",
    "logger",
    "thread",
    "process",
    "fork",
    "exec",
    "system",
    "eval",
    "pickle"
  ]

  @type suggestion :: map()

  @doc """
  Suggest a manifest from live introspection.
  """
  @spec suggest_manifest(String.t(), keyword()) :: suggestion()
  def suggest_manifest(module_path, opts \\ []) do
    depth = Keyword.get(opts, :depth, 1)

    {:ok, schema} = Discovery.discover(module_path, depth: depth)
    suggest_from_schema(schema, module_path, opts)
  end

  @doc """
  Suggest a manifest from a schema map.
  """
  @spec suggest_from_schema(map(), String.t(), keyword()) :: suggestion()
  def suggest_from_schema(schema, module_path, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    category = Keyword.get(opts, :category)
    elixir_module = Keyword.get(opts, :elixir_module) || default_module(module_path)
    prefix = Keyword.get(opts, :python_path_prefix, module_path)
    version = Map.get(schema, "library_version")

    {functions, types} = select_functions(schema, limit)

    %{}
    |> maybe_put("name", module_path)
    |> maybe_put("python_module", module_path)
    |> maybe_put("python_path_prefix", prefix)
    |> maybe_put("version", version)
    |> maybe_put("category", category && to_string(category))
    |> maybe_put("elixir_module", elixir_module)
    |> maybe_put("types", types)
    |> maybe_put("functions", functions)
  end

  defp select_functions(schema, limit) do
    functions =
      schema
      |> Map.get("functions", %{})
      |> Enum.map(fn {_name, desc} -> normalize_descriptor(desc) end)
      |> Enum.filter(fn desc -> is_binary(desc.name) end)
      |> Enum.reject(&exclude?/1)
      |> Enum.sort_by(&score/1, :desc)
      |> Enum.take(limit)

    types =
      functions
      |> Enum.flat_map(fn desc ->
        params = Map.get(desc, :parameters, [])

        Enum.map(params, fn param ->
          {Map.get(param, :name), Map.get(param, :type) || "any"}
        end)
      end)
      |> Enum.reject(fn {name, _} -> is_nil(name) end)
      |> Enum.into(%{})

    entries =
      Enum.map(functions, fn desc ->
        name = Map.get(desc, :name)
        args = Map.get(desc, :parameters, []) |> Enum.map(& &1.name)
        returns = Map.get(desc, :return_type) || "any"
        doc = Map.get(desc, :docstring)

        %{
          "name" => name,
          "args" => args,
          "returns" => returns,
          "doc" => doc
        }
      end)

    {entries, types}
  end

  defp normalize_descriptor(desc) when is_map(desc) do
    %{
      name: Map.get(desc, "name") || Map.get(desc, :name),
      docstring: Map.get(desc, "docstring") || Map.get(desc, :docstring) || "",
      parameters: normalize_parameters(Map.get(desc, "parameters") || Map.get(desc, :parameters)),
      return_type: Map.get(desc, "return_type") || Map.get(desc, :return_type)
    }
  end

  defp normalize_parameters(params) when is_list(params) do
    Enum.map(params, fn param ->
      %{
        name: Map.get(param, "name") || Map.get(param, :name),
        type: Map.get(param, "type") || Map.get(param, :type),
        required: Map.get(param, "required") || Map.get(param, :required, false)
      }
    end)
  end

  defp normalize_parameters(_), do: []

  defp exclude?(%{name: name, docstring: docstring, parameters: params}) do
    has_excluded_name?(name) or has_excluded_doc?(docstring) or has_excluded_params?(params)
  end

  defp has_excluded_name?(name) do
    name
    |> to_string()
    |> String.downcase()
    |> contains_any_pattern?(@exclude_patterns)
  end

  defp has_excluded_doc?(docstring) do
    docstring
    |> String.downcase()
    |> contains_any_pattern?(@exclude_patterns)
  end

  defp has_excluded_params?(params) do
    Enum.any?(params, &has_excluded_param_type?/1)
  end

  defp has_excluded_param_type?(param) do
    type_str =
      param.type
      |> to_string()
      |> String.downcase()

    contains_any_pattern?(type_str, ["callable", "io", "file", "path", "iterator", "generator"])
  end

  defp contains_any_pattern?(text, patterns) do
    Enum.any?(patterns, &String.contains?(text, &1))
  end

  defp score(%{docstring: docstring, parameters: params}) do
    doc_score = if docstring != "", do: 2, else: 0

    param_score =
      case length(params) do
        n when n <= 2 -> 2
        n when n <= 4 -> 1
        _ -> 0
      end

    doc_score + param_score
  end

  defp default_module(module_path) do
    parts = module_path |> String.split(".") |> Enum.map(&String.capitalize/1)
    ["SnakeBridge" | parts] |> Enum.join(".")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
