defmodule SnakeBridge.Docs do
  @moduledoc """
  On-demand documentation fetching with optional caching.
  """

  @cache_table :snakebridge_docs

  @spec get(module(), atom() | String.t()) :: String.t()
  def get(module, function) do
    key = {module, function}

    case lookup_cache(key) do
      {:hit, doc} ->
        doc

      :miss ->
        doc =
          case docs_source() do
            :python ->
              fetch_from_python(module, function)

            :metadata ->
              fetch_from_metadata(module, function) || "Documentation unavailable."

            :hybrid ->
              fetch_from_metadata(module, function) ||
                fetch_from_python(module, function)
          end

        maybe_cache(key, doc)
        doc
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

  defp fetch_from_metadata(_module, _function) do
    nil
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
    if cache_enabled?() do
      ensure_cache_table()

      case :ets.lookup(@cache_table, key) do
        [{^key, doc}] -> {:hit, doc}
        [] -> :miss
      end
    else
      :miss
    end
  end

  defp maybe_cache(key, doc) do
    if cache_enabled?() do
      ensure_cache_table()
      :ets.insert(@cache_table, {key, doc})
    end
  end

  defp cache_enabled? do
    Application.get_env(:snakebridge, :docs, [])
    |> Keyword.get(:cache_enabled, true)
  end

  defp ensure_cache_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])

      _ ->
        @cache_table
    end
  end
end
