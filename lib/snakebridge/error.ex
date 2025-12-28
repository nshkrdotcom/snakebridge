defmodule SnakeBridge.Error do
  @moduledoc """
  ML-specific error types for SnakeBridge.

  This module provides structured error types that translate Python/ML
  errors into Elixir exceptions with actionable suggestions.

  ## Available Error Types

  - `SnakeBridge.Error.ShapeMismatchError` - Tensor shape incompatibilities
  - `SnakeBridge.Error.OutOfMemoryError` - GPU/CPU memory exhaustion
  - `SnakeBridge.Error.DtypeMismatchError` - Tensor dtype incompatibilities

  ## Translation

  Use `SnakeBridge.ErrorTranslator` to automatically translate Python
  exceptions into these structured error types.

  ## Examples

      # Creating errors directly
      error = SnakeBridge.Error.ShapeMismatchError.new(:matmul,
        shape_a: [3, 4],
        shape_b: [5, 6]
      )

      # Raising errors
      raise SnakeBridge.Error.OutOfMemoryError, device: {:cuda, 0}

      # Translating Python errors
      translated = SnakeBridge.ErrorTranslator.translate(python_error)

  """

  # Re-export error modules for convenient access
  defdelegate shape_mismatch(operation, opts \\ []), to: __MODULE__.ShapeMismatchError, as: :new
  defdelegate out_of_memory(device, opts \\ []), to: __MODULE__.OutOfMemoryError, as: :new

  defdelegate dtype_mismatch(expected, got, opts \\ []),
    to: __MODULE__.DtypeMismatchError,
    as: :new
end
