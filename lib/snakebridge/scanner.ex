defmodule SnakeBridge.Scanner do
  @moduledoc """
  Scans project source files for Python library calls.
  """

  @type call_ref :: {module(), atom(), non_neg_integer()}

  @spec scan_project(SnakeBridge.Config.t()) :: [call_ref()]
  def scan_project(config) do
    library_modules = Enum.map(config.libraries, & &1.module_name)

    source_files(config)
    |> Task.async_stream(&scan_file(&1, library_modules), ordered: false)
    |> Enum.flat_map(fn {:ok, calls} -> calls end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_files(config) do
    scan_paths = config.scan_paths || ["lib"]
    scan_exclude = config.scan_exclude || []

    scan_paths
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.reject(fn path ->
      in_generated_dir?(path, config.generated_dir) or excluded_path?(path, scan_exclude)
    end)
  end

  defp in_generated_dir?(path, generated_dir) do
    String.starts_with?(path, generated_dir)
  end

  defp excluded_path?(path, patterns) do
    Enum.any?(patterns, fn pattern ->
      path in Path.wildcard(pattern)
    end)
  end

  defp scan_file(path, library_modules) do
    case File.read(path) do
      {:ok, content} ->
        case Code.string_to_quoted(content, file: path) do
          {:ok, ast} ->
            context = build_context(ast, library_modules)
            extract_calls(ast, context)

          {:error, _} ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp build_context(ast, library_modules) do
    {_, context} =
      Macro.prewalk(ast, %{aliases: %{}, imports: []}, fn
        {:alias, _, [{:__aliases__, _, parts} | opts]}, ctx ->
          module = Module.concat(parts)

          if library_module?(module, library_modules) do
            alias_name = alias_name(parts, opts)
            {nil, put_in(ctx, [:aliases, alias_name], module)}
          else
            {nil, ctx}
          end

        {:import, _, [{:__aliases__, _, parts} | opts]}, ctx ->
          module = Module.concat(parts)

          if library_module?(module, library_modules) do
            {nil, update_in(ctx, [:imports], &[{module, opts} | &1])}
          else
            {nil, ctx}
          end

        node, ctx ->
          {node, ctx}
      end)

    Map.put(context, :library_modules, library_modules)
  end

  defp alias_name(parts, opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, [name]} -> name
      nil -> List.last(parts)
    end
  end

  defp extract_calls(ast, context) do
    {_, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, parts}, function]}, _, args}, acc
        when is_atom(function) and is_list(args) ->
          module = resolve_module(parts, context)

          if module do
            {nil, [{module, function, length(args)} | acc]}
          else
            {nil, acc}
          end

        {function, _, args}, acc
        when is_atom(function) and is_list(args) ->
          case find_import(function, length(args), context) do
            {:ok, module} -> {nil, [{module, function, length(args)} | acc]}
            :not_found -> {nil, acc}
          end

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp resolve_module(parts, context) do
    case parts do
      [name] when is_atom(name) ->
        Map.get(context.aliases, name)

      _ ->
        module = Module.concat(parts)
        if library_module?(module, context.library_modules), do: module, else: nil
    end
  end

  defp library_module?(module, library_modules) do
    module_parts = Module.split(module)

    Enum.any?(library_modules, fn library_module ->
      library_parts = Module.split(library_module)
      Enum.take(module_parts, length(library_parts)) == library_parts
    end)
  end

  defp find_import(function, arity, context) do
    Enum.find_value(context.imports, :not_found, fn {module, opts} ->
      only = Keyword.get(opts, :only, nil)
      except = Keyword.get(opts, :except, [])

      cond do
        {function, arity} in except -> nil
        only && {function, arity} not in only -> nil
        true -> {:ok, module}
      end
    end)
  end
end
