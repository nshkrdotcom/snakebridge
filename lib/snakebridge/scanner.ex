defmodule SnakeBridge.Scanner do
  @moduledoc """
  Scans project source files for Python library calls.
  """

  @type call_ref :: {module(), atom(), non_neg_integer()}

  @spec scan_project(SnakeBridge.Config.t()) :: [call_ref()]
  def scan_project(config) do
    start_time = System.monotonic_time()
    library_modules = Enum.map(config.libraries, & &1.module_name)
    files = source_files(config)

    {calls, failures} =
      files
      |> Task.async_stream(&scan_file(&1, library_modules))
      |> Enum.zip(files)
      |> Enum.reduce({[], []}, fn
        {{:ok, calls}, _path}, {acc_calls, acc_failures} ->
          {calls ++ acc_calls, acc_failures}

        {{:exit, reason}, path}, {acc_calls, acc_failures} ->
          {acc_calls, [%{path: path, reason: reason, type: :exit} | acc_failures]}

        {{:error, reason}, path}, {acc_calls, acc_failures} ->
          {acc_calls, [%{path: path, reason: reason, type: :error} | acc_failures]}
      end)

    calls =
      calls
      |> Enum.uniq()
      |> Enum.sort()

    SnakeBridge.Telemetry.scan_stop(
      start_time,
      length(files),
      length(calls),
      config.scan_paths || ["lib"]
    )

    if failures != [] do
      raise SnakeBridge.ScanError, failures: Enum.reverse(failures)
    end

    calls
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
        {{:., _, [{:__aliases__, _, parts}, function]}, _, args} = node, acc
        when is_atom(function) and is_list(args) ->
          module = resolve_module(parts, context)

          if module do
            {node, [{module, function, length(args)} | acc]}
          else
            {node, acc}
          end

        {function, _, args} = node, acc
        when is_atom(function) and is_list(args) ->
          case find_import(function, length(args), context) do
            {:ok, module} -> {node, [{module, function, length(args)} | acc]}
            :not_found -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp resolve_module(parts, context) do
    module = Module.concat(parts)

    case parts do
      [name] when is_atom(name) ->
        Map.get(context.aliases, name) ||
          if library_module?(module, context.library_modules), do: module, else: nil

      _ ->
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
