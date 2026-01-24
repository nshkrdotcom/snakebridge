defmodule SnakeBridge.Docs do
  @moduledoc """
  On-demand documentation fetching with optional caching.
  """

  @cache_table :snakebridge_docs

  alias SnakeBridge.Manifest

  @spec get(module(), atom() | String.t()) :: String.t()
  def get(module, function) do
    start_time = System.monotonic_time()
    key = {module, function}

    case lookup_cache(key) do
      {:hit, doc} ->
        SnakeBridge.Telemetry.docs_fetch(start_time, module, function, :cache)
        doc

      :miss ->
        {doc, source} = fetch_doc_with_source(module, function)

        maybe_cache(key, doc)
        SnakeBridge.Telemetry.docs_fetch(start_time, module, function, source)
        doc
    end
  end

  @doc """
  Builds an ExDoc `groups_for_modules` keyword list using the SnakeBridge manifest.

  This keeps HexDocs navigation aligned with Python package paths, while
  remaining purely an Elixir configuration concern.

  ## Options

  - `:config` - `SnakeBridge.Config` struct (defaults to `SnakeBridge.Config.load/0`)
  - `:manifest` - manifest map (defaults to `SnakeBridge.Manifest.load/1`)
  - `:depth` - group depth beyond the library root (`:full` or non-negative integer, default: 1)
  - `:libraries` - list of library names to include (atoms or strings)
  - `:include_functions` - include module functions (default: true)
  - `:include_classes` - include class modules (default: true)
  """
  @spec groups_for_modules(keyword()) :: [{String.t(), [module()]}]
  def groups_for_modules(opts \\ []) do
    config = Keyword.get(opts, :config) || SnakeBridge.Config.load()
    manifest = Keyword.get(opts, :manifest) || Manifest.load(config)

    depth =
      case Keyword.get(opts, :depth, 1) do
        :full -> :full
        value when is_integer(value) -> value
        _ -> 1
      end

    include_functions = Keyword.get(opts, :include_functions, true)
    include_classes = Keyword.get(opts, :include_classes, true)
    only_libraries = Keyword.get(opts, :libraries)

    libraries = filter_libraries(config.libraries, only_libraries)

    entries =
      []
      |> maybe_add_function_entries(manifest, include_functions)
      |> maybe_add_class_entries(manifest, include_classes)

    entries
    |> Enum.reduce(%{}, fn entry, acc ->
      case process_entry(entry, libraries, depth) do
        nil ->
          acc

        {group, module} ->
          Map.update(acc, group, MapSet.new([module]), &MapSet.put(&1, module))
      end
    end)
    |> Enum.map(fn {group, modules} ->
      modules =
        modules
        |> Enum.map(&Module.split/1)
        |> Enum.sort()
        |> Enum.map(&Module.concat/1)

      {group, modules}
    end)
    |> Enum.sort_by(fn {group, _} -> group end)
  end

  @doc """
  Builds an ExDoc `nest_modules_by_prefix` list using the SnakeBridge manifest.

  This keeps the navigation tree aligned with generated Python packages.

  ## Options

  - `:config` - `SnakeBridge.Config` struct (defaults to `SnakeBridge.Config.load/0`)
  - `:manifest` - manifest map (defaults to `SnakeBridge.Manifest.load/1`)
  - `:libraries` - list of library names to include (atoms or strings)
  """
  @spec nest_modules_by_prefix(keyword()) :: [module()]
  def nest_modules_by_prefix(opts \\ []) do
    config = Keyword.get(opts, :config) || SnakeBridge.Config.load()
    manifest = Keyword.get(opts, :manifest) || Manifest.load(config)
    only_libraries = Keyword.get(opts, :libraries)

    libraries = filter_libraries(config.libraries, only_libraries)
    module_keys = Map.keys(Map.get(manifest, "modules", %{}))

    roots =
      module_keys
      |> Enum.map(&library_for_module(&1, libraries))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.module_name)
      |> Enum.uniq()

    roots =
      if roots == [] do
        Enum.map(libraries, & &1.module_name)
      else
        roots
      end

    Enum.sort(roots)
  end

  defp fetch_doc_with_source(module, function) do
    case docs_source() do
      :python ->
        {fetch_from_python(module, function), :python}

      :metadata ->
        {fetch_from_metadata(module, function) || "Documentation unavailable.", :metadata}

      :hybrid ->
        fetch_hybrid_doc(module, function)
    end
  end

  defp fetch_hybrid_doc(module, function) do
    case fetch_from_metadata(module, function) do
      nil -> {fetch_from_python(module, function), :python}
      metadata -> {metadata, :metadata}
    end
  end

  @spec search(module(), String.t()) :: list()
  def search(module, query) when is_binary(query) do
    query = query |> String.trim() |> String.downcase()

    module
    |> functions_for_search()
    |> Enum.map(fn {name, summary} -> {name, summary, score(name, query)} end)
    |> Enum.filter(fn {_name, _summary, relevance} -> relevance > 0.3 end)
    |> Enum.sort_by(fn {_name, _summary, relevance} -> -relevance end)
    |> Enum.take(10)
    |> Enum.map(fn {name, summary, relevance} ->
      %{name: name, summary: summary, relevance: relevance}
    end)
  end

  defp docs_source do
    Application.get_env(:snakebridge, :docs, [])
    |> Keyword.get(:source, :python)
  end

  defp functions_for_search(module) do
    if function_exported?(module, :__functions__, 0) do
      module.__functions__()
      |> Enum.map(fn {name, _arity, _mod, summary} ->
        {name, summary |> to_string()}
      end)
    else
      []
    end
  end

  defp score(name, query) do
    name = name |> to_string() |> String.downcase()

    cond do
      query == "" -> 0.0
      name == query -> 1.0
      String.starts_with?(name, query) -> 0.9
      String.contains?(name, query) -> 0.7
      true -> 0.0
    end
  end

  defp maybe_add_function_entries(entries, _manifest, false), do: entries

  defp maybe_add_function_entries(entries, manifest, true) do
    entries ++
      (manifest
       |> Map.get("symbols", %{})
       |> Map.values()
       |> Enum.map(fn info -> {info["python_module"] || "", info["module"] || ""} end))
  end

  defp maybe_add_class_entries(entries, _manifest, false), do: entries

  defp maybe_add_class_entries(entries, manifest, true) do
    entries ++
      (manifest
       |> Map.get("classes", %{})
       |> Map.values()
       |> Enum.map(fn info -> {info["python_module"] || "", info["module"] || ""} end))
  end

  defp filter_libraries(libraries, nil), do: libraries

  defp filter_libraries(libraries, only) do
    only =
      only
      |> List.wrap()
      |> Enum.map(&to_string/1)

    Enum.filter(libraries, fn library ->
      to_string(library.python_name) in only
    end)
  end

  defp library_for_module(python_module, libraries) do
    libraries
    |> Enum.filter(fn library ->
      String.starts_with?(python_module, library.python_name)
    end)
    |> Enum.max_by(fn library -> String.length(library.python_name) end, fn -> nil end)
  end

  defp group_name_for(python_module, library, depth) do
    if depth == :full do
      python_module
    else
      depth = max(depth, 0)
      root_parts = String.split(library.python_name, ".")
      module_parts = String.split(python_module, ".")
      extra_parts = Enum.drop(module_parts, length(root_parts))

      if extra_parts == [] or depth == 0 do
        Enum.join(root_parts, ".")
      else
        Enum.join(root_parts ++ Enum.take(extra_parts, depth), ".")
      end
    end
  end

  defp process_entry({python_module, elixir_module}, libraries, depth) do
    if python_module in [nil, ""] or elixir_module in [nil, ""] do
      nil
    else
      process_valid_entry(python_module, elixir_module, libraries, depth)
    end
  end

  defp process_valid_entry(python_module, elixir_module, libraries, depth) do
    case library_for_module(python_module, libraries) do
      nil ->
        nil

      library ->
        group = group_name_for(python_module, library, depth)

        module =
          elixir_module
          |> to_string()
          |> String.split(".")
          |> Module.concat()

        {group, module}
    end
  end

  defp fetch_from_metadata(module, function) do
    function_name = to_string(function)

    with {:docs_v1, _, _, _, _, _, docs} <- Code.fetch_docs(module),
         entry when not is_nil(entry) <- Enum.find(docs, &doc_entry_matches?(&1, function_name)),
         docstring when is_binary(docstring) <- docstring_from_entry(entry) do
      normalize_docstring(docstring)
    else
      _ -> nil
    end
  end

  defp doc_entry_matches?({{kind, name, _arity}, _, _, _, _}, function_name)
       when kind in [:function, :macro] and is_atom(name) do
    Atom.to_string(name) == function_name
  end

  defp doc_entry_matches?({{name, _arity}, _, _, _, _}, function_name) when is_atom(name) do
    Atom.to_string(name) == function_name
  end

  defp doc_entry_matches?(_entry, _function_name), do: false

  defp docstring_from_entry({_id, _anno, _signature, doc, _metadata}) do
    case doc do
      :hidden -> nil
      :none -> nil
      {_, text} when is_binary(text) -> text
      text when is_binary(text) -> text
      _ -> nil
    end
  end

  defp normalize_docstring(docstring) do
    case String.trim(docstring) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp fetch_from_python(module, function) do
    python_name = python_module_name(module)
    script = doc_script()

    case python_runner().run(script, [python_name, to_string(function)], []) do
      {:ok, output} -> String.trim(output)
      {:error, _} -> "Documentation unavailable."
    end
  end

  defp python_runner do
    Application.get_env(:snakebridge, :python_runner, SnakeBridge.PythonRunner.System)
  end

  defp python_module_name(module) do
    if function_exported?(module, :__snakebridge_python_name__, 0) do
      module.__snakebridge_python_name__()
    else
      module
      |> Module.split()
      |> Enum.map_join(".", &Macro.underscore/1)
    end
  end

  defp doc_script do
    ~S"""
    import importlib
    import inspect
    import sys

    module_name = sys.argv[1]
    function_name = sys.argv[2]

    module = importlib.import_module(module_name)
    obj = getattr(module, function_name, None)
    if obj is None:
        print("Function not found.")
    else:
        print(inspect.getdoc(obj) or "Documentation unavailable.")
    """
  end

  defp lookup_cache(key) do
    with true <- cache_enabled?(),
         table when table != :undefined <- cache_table() do
      lookup_cache_table(key)
    else
      _ -> :miss
    end
  end

  defp lookup_cache_table(key) do
    case :ets.lookup(@cache_table, key) do
      [{^key, doc}] -> {:hit, doc}
      [] -> :miss
    end
  end

  defp maybe_cache(key, doc) do
    if cache_enabled?() do
      case cache_table() do
        :undefined -> :ok
        _ -> :ets.insert(@cache_table, {key, doc})
      end
    end
  end

  defp cache_enabled? do
    Application.get_env(:snakebridge, :docs, [])
    |> Keyword.get(:cache_enabled, true)
  end

  defp cache_table do
    case :ets.whereis(@cache_table) do
      :undefined -> :undefined
      _ -> @cache_table
    end
  end
end
