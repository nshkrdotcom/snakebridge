defmodule SnakeBridge.ErrorTranslator do
  @moduledoc """
  Translates Python/ML errors into structured SnakeBridge errors.

  This module recognizes common ML error patterns from PyTorch, NumPy,
  and other ML libraries, and translates them into structured error
  types with actionable suggestions.

  ## Supported Error Types

  - `SnakeBridge.Error.ShapeMismatchError` - Tensor shape incompatibilities
  - `SnakeBridge.Error.OutOfMemoryError` - GPU/CPU memory exhaustion
  - `SnakeBridge.Error.DtypeMismatchError` - Tensor dtype incompatibilities

  ## Examples

      iex> error = %RuntimeError{message: "CUDA out of memory"}
      iex> SnakeBridge.ErrorTranslator.translate(error)
      %SnakeBridge.Error.OutOfMemoryError{device: {:cuda, 0}, ...}

  """

  alias SnakeBridge.Error.{DtypeMismatchError, OutOfMemoryError, ShapeMismatchError}

  # Mapping from normalized dtype strings to Elixir atoms
  @dtype_map %{
    # PyTorch short names
    "float" => :float32,
    "double" => :float64,
    "half" => :float16,
    "long" => :int64,
    "int" => :int32,
    "short" => :int16,
    "byte" => :uint8,
    "char" => :int8,
    "bool" => :bool,
    # PyTorch qualified names
    "torch.float32" => :float32,
    "torch.float64" => :float64,
    "torch.float16" => :float16,
    "torch.int64" => :int64,
    "torch.int32" => :int32,
    "torch.int16" => :int16,
    "torch.int8" => :int8,
    "torch.uint8" => :uint8,
    "torch.bool" => :bool,
    "torch.bfloat16" => :bfloat16
  }

  @doc """
  Translates a Python/ML error to a structured SnakeBridge error.

  Returns the original error if it cannot be translated.
  """
  @spec translate(Exception.t() | nil, String.t() | nil) :: Exception.t() | nil
  def translate(error, traceback \\ nil)

  def translate(nil, _traceback), do: nil

  def translate(%RuntimeError{message: message} = error, traceback) do
    case translate_message(message) do
      nil -> error
      translated -> maybe_add_traceback(translated, traceback)
    end
  end

  def translate(error, _traceback), do: error

  @doc """
  Translates an error message string to a structured error.

  Returns nil if the message cannot be translated.
  """
  @spec translate_message(String.t()) :: Exception.t() | nil
  def translate_message(message) when is_binary(message) do
    cond do
      shape_mismatch?(message) -> translate_shape_error(message)
      oom_error?(message) -> translate_oom_error(message)
      dtype_mismatch?(message) -> translate_dtype_error(message)
      true -> nil
    end
  end

  @doc """
  Converts a Python/PyTorch dtype string to an Elixir atom.

  ## Examples

      iex> SnakeBridge.ErrorTranslator.dtype_from_string("Float")
      :float32

      iex> SnakeBridge.ErrorTranslator.dtype_from_string("torch.float64")
      :float64

  """
  @spec dtype_from_string(String.t()) :: atom()
  def dtype_from_string(dtype_str) do
    normalized = dtype_str |> String.trim() |> String.downcase()

    case Map.fetch(@dtype_map, normalized) do
      {:ok, dtype} -> dtype
      :error -> String.to_atom(String.replace(normalized, ".", "_"))
    end
  end

  # Shape mismatch detection patterns
  defp shape_mismatch?(message) do
    String.contains?(message, "shapes cannot be multiplied") or
      String.contains?(message, "size of tensor") or
      String.contains?(message, "incompatible shapes") or
      String.contains?(message, "Dimension out of range") or
      String.contains?(message, "shape mismatch") or
      String.contains?(message, "dimension mismatch")
  end

  # OOM error detection patterns
  defp oom_error?(message) do
    String.contains?(message, "out of memory") or
      String.contains?(message, "OutOfMemory") or
      String.contains?(message, "OOM")
  end

  # Dtype mismatch detection patterns
  defp dtype_mismatch?(message) do
    String.contains?(message, "expected scalar type") or
      String.contains?(message, "expected dtype") or
      String.contains?(message, "type mismatch")
  end

  # Translate shape errors
  defp translate_shape_error(message) do
    cond do
      # mat1 and mat2 shapes cannot be multiplied (3x4 and 5x6)
      match = Regex.run(~r/shapes cannot be multiplied \((\d+)x(\d+) and (\d+)x(\d+)\)/, message) ->
        [_, a_rows, a_cols, b_rows, b_cols] = match

        ShapeMismatchError.new(:matmul,
          shape_a: [String.to_integer(a_rows), String.to_integer(a_cols)],
          shape_b: [String.to_integer(b_rows), String.to_integer(b_cols)],
          message: extract_core_message(message)
        )

      # Broadcasting shape mismatch
      String.contains?(message, "broadcasting") ->
        shapes = extract_broadcast_shapes(message)

        ShapeMismatchError.new(:broadcast,
          shape_a: elem(shapes, 0),
          shape_b: elem(shapes, 1),
          message: extract_core_message(message)
        )

      # Dimension errors
      String.contains?(message, "Dimension") ->
        ShapeMismatchError.new(:index,
          message: extract_core_message(message)
        )

      # Size mismatch
      String.contains?(message, "size of tensor") ->
        ShapeMismatchError.new(:elementwise,
          message: extract_core_message(message)
        )

      # Generic shape error
      true ->
        ShapeMismatchError.new(:unknown,
          message: extract_core_message(message)
        )
    end
  end

  # Translate OOM errors
  defp translate_oom_error(message) do
    device = detect_device(message)
    memory_info = extract_memory_info(message)

    OutOfMemoryError.new(device,
      requested_mb: memory_info[:requested],
      available_mb: memory_info[:available],
      total_mb: memory_info[:total],
      message: extract_core_message(message)
    )
  end

  # Translate dtype errors
  defp translate_dtype_error(message) do
    {expected, got} = extract_dtype_info(message)

    DtypeMismatchError.new(expected, got, message: extract_core_message(message))
  end

  # Device detection from error message
  defp detect_device(message) do
    cond do
      String.contains?(message, "MPS") -> :mps
      match = Regex.run(~r/GPU (\d+)/, message) -> {:cuda, String.to_integer(Enum.at(match, 1))}
      String.contains?(message, "CUDA") -> {:cuda, 0}
      String.contains?(message, "cuda") -> {:cuda, 0}
      true -> :cpu
    end
  end

  # Extract memory information from OOM message
  defp extract_memory_info(message) do
    requested = extract_memory_value(message, ~r/allocate (\d+) MiB/)
    total = extract_memory_value(message, ~r/(\d+) MiB total/)
    available = extract_memory_value(message, ~r/(\d+) MiB free/)

    %{requested: requested, total: total, available: available}
  end

  defp extract_memory_value(message, pattern) do
    case Regex.run(pattern, message) do
      [_, value] -> String.to_integer(value)
      nil -> nil
    end
  end

  # Extract dtype info from error message
  defp extract_dtype_info(message) do
    cond do
      # "expected scalar type Float but found Double"
      match = Regex.run(~r/expected scalar type (\w+) but found (\w+)/, message) ->
        [_, expected, got] = match
        {dtype_from_string(expected), dtype_from_string(got)}

      # "expected dtype torch.float32 but got torch.int64"
      match = Regex.run(~r/expected dtype ([\w.]+) but got ([\w.]+)/, message) ->
        [_, expected, got] = match
        {dtype_from_string(expected), dtype_from_string(got)}

      true ->
        {:unknown, :unknown}
    end
  end

  # Extract broadcast shapes from message
  defp extract_broadcast_shapes(message) do
    case Regex.run(~r/\[([^\]]+)\] vs \[([^\]]+)\]/, message) do
      [_, a, b] ->
        {parse_shape(a), parse_shape(b)}

      nil ->
        {nil, nil}
    end
  end

  defp parse_shape(shape_str) do
    shape_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_integer/1)
  end

  # Extract the core error message
  defp extract_core_message(message) do
    message
    |> String.trim()
    |> String.replace(~r/^RuntimeError:\s*/, "")
    |> String.replace(~r/^torch\.\w+Error:\s*/, "")
    |> String.split("\n")
    |> List.first()
    |> String.trim()
  end

  # Add traceback if provided
  defp maybe_add_traceback(error, nil), do: error

  defp maybe_add_traceback(%{__struct__: _} = error, traceback) do
    Map.put(error, :python_traceback, traceback)
  end
end
