defmodule SnakeBridge.Compiler.IntrospectionRunner do
  @moduledoc false

  alias SnakeBridge.Introspector

  @spec run(list()) :: list()
  def run(targets) do
    {updates, errors} =
      targets
      |> Introspector.introspect_batch()
      |> Enum.reduce({[], []}, fn {library, result, python_module}, {acc, errs} ->
        case result do
          {:ok, infos} ->
            {[{library, python_module, infos} | acc], errs}

          {:error, reason} ->
            log_introspection_error(library, python_module, reason)
            emit_introspection_error_telemetry(library, python_module, reason)
            {acc, [{library, python_module, reason} | errs]}
        end
      end)

    if errors != [] do
      show_introspection_summary(errors)
    end

    Enum.reverse(updates)
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

  defp show_introspection_summary(errors) do
    count = length(errors)

    message = """

    ================================================================================
    SnakeBridge Introspection Summary
    ================================================================================
    #{count} introspection error(s) occurred. Some symbols may be missing from
    the generated bindings.

    To resolve:
      1. Check the errors above for details
      2. Ensure Python packages are installed: mix snakebridge.setup
      3. Check for import errors in your Python dependencies
      4. Re-run: mix compile

    The compilation will continue, but affected symbols will not be available.
    ================================================================================
    """

    Mix.shell().info(message)
  end
end
