defmodule SnakeBridge.Error.ShapeMismatchError do
  @moduledoc """
  Error for tensor shape incompatibilities.

  This error provides detailed information about shape mismatches including
  the operation that failed, the shapes involved, and actionable suggestions.

  ## Examples

      iex> error = %SnakeBridge.Error.ShapeMismatchError{
      ...>   operation: :matmul,
      ...>   shape_a: [3, 4],
      ...>   shape_b: [2, 5],
      ...>   message: "Cannot multiply matrices with incompatible shapes",
      ...>   suggestion: "A has 4 columns but B has 2 rows. Transpose B."
      ...> }
      iex> Exception.message(error)
      "Shape mismatch in matmul..."

  """

  @type t :: %__MODULE__{
          operation: atom(),
          shape_a: [non_neg_integer()] | nil,
          shape_b: [non_neg_integer()] | nil,
          expected: String.t() | nil,
          got: String.t() | nil,
          message: String.t(),
          suggestion: String.t(),
          python_traceback: String.t() | nil
        }

  defexception [
    :operation,
    :shape_a,
    :shape_b,
    :expected,
    :got,
    :python_traceback,
    message: "Shape mismatch",
    suggestion: "Check tensor shapes"
  ]

  @impl Exception
  def message(%__MODULE__{} = error) do
    parts = ["Shape mismatch in #{error.operation}"]

    parts =
      if error.shape_a do
        parts ++ ["  Shape A: #{inspect(error.shape_a)}"]
      else
        parts
      end

    parts =
      if error.shape_b do
        parts ++ ["  Shape B: #{inspect(error.shape_b)}"]
      else
        parts
      end

    parts =
      if error.expected do
        parts ++ ["  Expected: #{error.expected}"]
      else
        parts
      end

    parts =
      if error.got do
        parts ++ ["  Got: #{error.got}"]
      else
        parts
      end

    parts = parts ++ ["", error.message, "", "Suggestion: #{error.suggestion}"]

    parts
    |> Enum.join("\n")
    |> String.trim()
  end

  @doc """
  Creates a ShapeMismatchError error from context.
  """
  @spec new(atom(), keyword()) :: t()
  def new(operation, opts \\ []) do
    shape_a = Keyword.get(opts, :shape_a)
    shape_b = Keyword.get(opts, :shape_b)

    suggestion =
      Keyword.get(opts, :suggestion) ||
        generate_suggestion(operation, shape_a, shape_b)

    %__MODULE__{
      operation: operation,
      shape_a: shape_a,
      shape_b: shape_b,
      expected: Keyword.get(opts, :expected),
      got: Keyword.get(opts, :got),
      message: Keyword.get(opts, :message, "Shapes are incompatible for #{operation}"),
      suggestion: suggestion,
      python_traceback: Keyword.get(opts, :python_traceback)
    }
  end

  @doc """
  Generates a suggestion based on the operation and shapes.
  """
  @spec generate_suggestion(atom(), [non_neg_integer()] | nil, [non_neg_integer()] | nil) ::
          String.t()
  def generate_suggestion(:matmul, shape_a, shape_b)
      when is_list(shape_a) and is_list(shape_b) do
    a_cols = List.last(shape_a)
    b_rows = List.first(shape_b)

    if a_cols != b_rows do
      "For matrix multiplication, A columns (#{a_cols}) must equal B rows (#{b_rows}). " <>
        "Try: tensor.transpose(dim0, dim1) if B needs transposing"
    else
      "Check that tensor shapes are compatible for matrix multiplication."
    end
  end

  def generate_suggestion(_operation, shape_a, shape_b)
      when is_list(shape_a) and is_list(shape_b) do
    if length(shape_a) != length(shape_b) do
      "Tensors have different number of dimensions (#{length(shape_a)} vs #{length(shape_b)}). " <>
        "Use unsqueeze/squeeze to adjust dimensions."
    else
      mismatched = find_mismatched_dim(shape_a, shape_b)

      if mismatched do
        "Shapes differ at dimension #{mismatched}. Check broadcasting rules or reshape tensors."
      else
        "Verify tensor shapes are compatible for this operation."
      end
    end
  end

  def generate_suggestion(_operation, _shape_a, _shape_b) do
    "Verify tensor shapes are compatible for this operation."
  end

  defp find_mismatched_dim(shape_a, shape_b) do
    shape_a
    |> Enum.zip(shape_b)
    |> Enum.with_index()
    |> Enum.find_value(fn
      {{x, y}, idx} when x != y and x != 1 and y != 1 -> idx
      _ -> nil
    end)
  end
end
