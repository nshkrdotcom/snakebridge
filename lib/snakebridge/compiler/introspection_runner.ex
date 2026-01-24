defmodule SnakeBridge.Compiler.IntrospectionRunner do
  @moduledoc false

  alias SnakeBridge.Introspector

  @spec run(list()) :: {list(), list()}
  def run(targets) do
    {updates, errors} =
      targets
      |> Introspector.introspect_batch()
      |> Enum.reduce({[], []}, fn {library, result, python_module}, {acc, errs} ->
        case result do
          {:ok, infos} ->
            {[{library, python_module, infos} | acc], errs}

          {:error, reason} ->
            emit_introspection_error_telemetry(library, python_module, reason)
            {acc, [{library, python_module, reason} | errs]}
        end
      end)

    {Enum.reverse(updates), Enum.reverse(errors)}
  end

  @doc false
  def log_introspection_error(library, python_module, reason) do
    formatted = format_introspection_error(library, python_module, reason)
    Mix.shell().info(formatted)
  end

  @doc false
  def format_introspection_error(library, python_module, reason) do
    library_name = get_library_name(library)
    base = build_base_message(library_name, python_module)
    format_reason(base, reason)
  end

  defp get_library_name(library) when is_map(library), do: library.name || library.python_name
  defp get_library_name(library), do: inspect(library)

  defp build_base_message(library_name, python_module) do
    base = "  [warning] Introspection failed for #{library_name}"

    if python_module && python_module != library_name do
      base <> ".#{python_module}"
    else
      base
    end
  end

  defp format_reason(base, %{type: _type, message: message, suggestion: suggestion}) do
    lines = [base, "    Error: #{message}"]
    lines = if suggestion, do: lines ++ ["    Suggestion: #{suggestion}"], else: lines
    Enum.join(lines, "\n")
  end

  defp format_reason(base, %{message: message}) do
    base <> "\n    Error: #{message}"
  end

  defp format_reason(base, message) when is_binary(message) do
    base <> "\n    Error: #{message}"
  end

  defp format_reason(base, reason) do
    base <> "\n    Error: #{inspect(reason)}"
  end

  defp emit_introspection_error_telemetry(library, python_module, reason) do
    library_name =
      if is_map(library), do: library.name || library.python_name, else: inspect(library)

    error_type =
      case reason do
        %{type: type} -> type
        _ -> :unknown
      end

    if telemetry_ready?() do
      :telemetry.execute(
        [:snakebridge, :introspection, :error],
        %{count: 1},
        %{
          library: library_name,
          python_module: python_module,
          error_type: error_type,
          reason: reason
        }
      )
    end
  end

  defp telemetry_ready? do
    Code.ensure_loaded?(:telemetry) and :ets.whereis(:telemetry_handler_table) != :undefined
  end
end
