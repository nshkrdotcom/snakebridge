defmodule SnakeBridge.Error.DtypeMismatchError do
  @moduledoc """
  Error for tensor dtype incompatibilities.

  Provides information about expected vs actual dtypes and
  suggestions for converting between types.

  ## Examples

      iex> error = %SnakeBridge.Error.DtypeMismatchError{
      ...>   expected: :float32,
      ...>   got: :float64,
      ...>   operation: :matmul,
      ...>   message: "Expected float32 but got float64"
      ...> }
      iex> Exception.message(error)
      "Dtype mismatch in matmul..."

  """

  @type dtype :: :float16 | :float32 | :float64 | :int32 | :int64 | :bool | atom()

  @type t :: %__MODULE__{
          expected: dtype(),
          got: dtype(),
          operation: atom() | nil,
          message: String.t(),
          suggestion: String.t(),
          python_traceback: String.t() | nil
        }

  defexception [
    :expected,
    :got,
    :operation,
    :python_traceback,
    message: "Dtype mismatch",
    suggestion: "Convert tensor to the expected dtype"
  ]

  @impl Exception
  def message(%__MODULE__{} = error) do
    op_str = if error.operation, do: " in #{error.operation}", else: ""

    """
    Dtype mismatch#{op_str}

      Expected: #{format_dtype(error.expected)}
      Got: #{format_dtype(error.got)}

    #{error.message}

    Suggestion: #{error.suggestion}
    """
    |> String.trim()
  end

  @doc """
  Creates a DtypeMismatchError error with conversion suggestion.
  """
  @spec new(dtype(), dtype(), keyword()) :: t()
  def new(expected, got, opts \\ []) do
    suggestion =
      Keyword.get(opts, :suggestion) ||
        generate_suggestion(expected, got)

    %__MODULE__{
      expected: expected,
      got: got,
      operation: Keyword.get(opts, :operation),
      message: Keyword.get(opts, :message, "Types do not match"),
      suggestion: suggestion,
      python_traceback: Keyword.get(opts, :python_traceback)
    }
  end

  @doc """
  Generates a suggestion for converting between dtypes.
  """
  @spec generate_suggestion(dtype(), dtype()) :: String.t()
  def generate_suggestion(expected, got) do
    _from = format_dtype(got)
    to = format_dtype(expected)

    cond do
      precision_loss?(got, expected) ->
        "Convert with tensor.to(torch.#{to}) - note: this may lose precision"

      requires_explicit?(got, expected) ->
        "Convert with tensor.to(torch.#{to})"

      true ->
        "Use tensor.to(torch.#{to}) or tensor.type(torch.#{expected_torch_type(expected)})"
    end
  end

  defp format_dtype(dtype) when is_atom(dtype) do
    dtype
    |> Atom.to_string()
    |> String.replace("_", "")
  end

  defp format_dtype(dtype), do: inspect(dtype)

  defp expected_torch_type(:float16), do: "HalfTensor"
  defp expected_torch_type(:float32), do: "FloatTensor"
  defp expected_torch_type(:float64), do: "DoubleTensor"
  defp expected_torch_type(:int32), do: "IntTensor"
  defp expected_torch_type(:int64), do: "LongTensor"
  defp expected_torch_type(:bool), do: "BoolTensor"
  defp expected_torch_type(other), do: Atom.to_string(other)

  # Detect if conversion loses precision
  defp precision_loss?(from, to) do
    precision_rank(from) > precision_rank(to)
  end

  defp precision_rank(:float64), do: 3
  defp precision_rank(:float32), do: 2
  defp precision_rank(:float16), do: 1
  defp precision_rank(:int64), do: 2
  defp precision_rank(:int32), do: 1
  defp precision_rank(_), do: 0

  # Detect if explicit conversion is required (e.g., float to int)
  defp requires_explicit?(from, to) do
    float_type?(from) != float_type?(to)
  end

  defp float_type?(dtype) when dtype in [:float16, :float32, :float64], do: true
  defp float_type?(_), do: false
end
