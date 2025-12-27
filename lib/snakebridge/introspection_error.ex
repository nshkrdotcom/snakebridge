defmodule SnakeBridge.IntrospectionError do
  @moduledoc """
  Structured error for Python introspection failures.
  """

  defexception [:type, :package, :message, :python_error, :suggestion]

  @type t :: %__MODULE__{
          type: :package_not_found | :import_error | :timeout | :introspection_bug,
          package: String.t() | nil,
          message: String.t(),
          python_error: String.t() | nil,
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{message: message, suggestion: suggestion}) do
    if suggestion do
      message <> "\n\nSuggestion: " <> suggestion
    else
      message
    end
  end

  @doc """
  Parses Python stderr to classify the error.
  """
  @spec from_python_output(String.t(), String.t()) :: t()
  def from_python_output(output, package) when is_binary(output) do
    output = String.trim(output)

    cond do
      module_not_found?(output) ->
        missing = extract_missing_package(output) || package

        %__MODULE__{
          type: :package_not_found,
          package: missing,
          message: "Package '#{missing}' not found",
          python_error: output,
          suggestion: "Run: mix snakebridge.setup"
        }

      import_error?(output) ->
        %__MODULE__{
          type: :import_error,
          package: package,
          message: extract_import_error(output),
          python_error: output,
          suggestion: "Check library dependencies or install optional extras"
        }

      timeout_error?(output) ->
        %__MODULE__{
          type: :timeout,
          package: package,
          message: extract_timeout_error(output),
          python_error: output,
          suggestion: "Increase introspection timeout or retry"
        }

      true ->
        %__MODULE__{
          type: :introspection_bug,
          package: package,
          message: extract_generic_error(output),
          python_error: output,
          suggestion: "Please report this issue with the Python error output"
        }
    end
  end

  defp module_not_found?(output) do
    String.contains?(output, "ModuleNotFoundError")
  end

  defp import_error?(output) do
    String.contains?(output, "ImportError")
  end

  defp timeout_error?(output) do
    String.contains?(output, "TimeoutError") or String.contains?(output, "timed out")
  end

  defp extract_missing_package(output) do
    case Regex.run(~r/ModuleNotFoundError: No module named ['"]([^'"]+)['"]/m, output) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp extract_import_error(output) do
    case Regex.run(~r/ImportError: (.+)$/m, output) do
      [_, msg] -> String.trim(msg)
      _ -> "ImportError"
    end
  end

  defp extract_timeout_error(output) do
    case Regex.run(~r/TimeoutError: (.+)$/m, output) do
      [_, msg] -> String.trim(msg)
      _ -> "Introspection timed out"
    end
  end

  defp extract_generic_error(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find(&String.contains?(&1, "Error"))
    |> case do
      nil -> "Unexpected error during introspection"
      line -> String.trim(line)
    end
  end
end
