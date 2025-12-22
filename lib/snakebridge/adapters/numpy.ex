defmodule SnakeBridge.Adapters.Numpy do
  @moduledoc """
  Elixir interface for NumPy array operations.

  Provides convenient functions for working with NumPy arrays
  through SnakeBridge, with results returned as Elixir lists.

  ## Usage

      alias SnakeBridge.Adapters.Numpy

      # Create arrays
      {:ok, result} = Numpy.zeros([3, 3], dtype: "float64")
      # => %{data: [[0.0, 0.0, 0.0], ...], shape: [3, 3], dtype: "float64"}

      {:ok, result} = Numpy.arange(0, 10, 2)
      # => %{data: [0, 2, 4, 6, 8], shape: [5], dtype: "int64"}

      # Math operations
      {:ok, result} = Numpy.mean([[1, 2], [3, 4]])
      # => %{result: 2.5}

      {:ok, result} = Numpy.dot([1, 2], [3, 4])
      # => %{result: 11.0}

  ## Data Types

  Supported dtypes:
  - float32, float64 (floats)
  - int8, int16, int32, int64 (signed integers)
  - uint8, uint16, uint32, uint64 (unsigned integers)
  - bool
  - complex64, complex128

  ## Serialization

  All arrays are serialized as nested Elixir lists. For large arrays,
  consider using the streaming API or chunked operations.
  """

  alias SnakeBridge.Runtime

  @default_timeout 30_000

  @doc """
  Create an array from nested lists.

  ## Options

  - `:dtype` - Data type (e.g., "float64", "int32")
  - `:shape` - Optional shape to reshape to
  - `:timeout` - Operation timeout in ms (default: 30000)

  ## Examples

      Numpy.array([[1, 2], [3, 4]], dtype: "float32")
  """
  @spec array(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def array(data, opts \\ []) do
    call_numpy_tool(
      "np_create_array",
      %{
        "data" => data,
        "dtype" => Keyword.get(opts, :dtype),
        "shape" => Keyword.get(opts, :shape)
      },
      opts
    )
  end

  @doc """
  Create an array of zeros.

  ## Examples

      Numpy.zeros([3, 3])
      Numpy.zeros([2, 4], dtype: "int32")
  """
  @spec zeros(list(integer()), keyword()) :: {:ok, map()} | {:error, term()}
  def zeros(shape, opts \\ []) do
    call_numpy_tool(
      "np_zeros",
      %{
        "shape" => shape,
        "dtype" => Keyword.get(opts, :dtype, "float64")
      },
      opts
    )
  end

  @doc """
  Create an array of ones.

  ## Examples

      Numpy.ones([2, 3])
      Numpy.ones([5], dtype: "float32")
  """
  @spec ones(list(integer()), keyword()) :: {:ok, map()} | {:error, term()}
  def ones(shape, opts \\ []) do
    call_numpy_tool(
      "np_ones",
      %{
        "shape" => shape,
        "dtype" => Keyword.get(opts, :dtype, "float64")
      },
      opts
    )
  end

  @doc """
  Create an array with evenly spaced values within an interval.

  ## Examples

      Numpy.arange(10)           # [0, 1, 2, ..., 9]
      Numpy.arange(2, 10)        # [2, 3, 4, ..., 9]
      Numpy.arange(2, 10, 2)     # [2, 4, 6, 8]
  """
  @spec arange(number(), number() | nil, number(), keyword()) :: {:ok, map()} | {:error, term()}
  def arange(start, stop \\ nil, step \\ 1, opts \\ []) do
    call_numpy_tool(
      "np_arange",
      %{
        "start" => start,
        "stop" => stop,
        "step" => step,
        "dtype" => Keyword.get(opts, :dtype)
      },
      opts
    )
  end

  @doc """
  Create an array of evenly spaced numbers over an interval.

  ## Examples

      Numpy.linspace(0, 1, 5)    # [0.0, 0.25, 0.5, 0.75, 1.0]
      Numpy.linspace(0, 10, 3)   # [0.0, 5.0, 10.0]
  """
  @spec linspace(number(), number(), integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def linspace(start, stop, num \\ 50, opts \\ []) do
    call_numpy_tool(
      "np_linspace",
      %{
        "start" => start,
        "stop" => stop,
        "num" => num,
        "dtype" => Keyword.get(opts, :dtype)
      },
      opts
    )
  end

  @doc """
  Compute the arithmetic mean.

  ## Examples

      Numpy.mean([1, 2, 3, 4])           # 2.5
      Numpy.mean([[1, 2], [3, 4]])       # 2.5
      Numpy.mean([[1, 2], [3, 4]], axis: 0)  # [2.0, 3.0]
  """
  @spec mean(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def mean(data, opts \\ []) do
    call_numpy_tool(
      "np_mean",
      %{
        "data" => data,
        "axis" => Keyword.get(opts, :axis)
      },
      opts
    )
  end

  @doc """
  Compute the sum of array elements.

  ## Examples

      Numpy.sum([1, 2, 3])               # 6
      Numpy.sum([[1, 2], [3, 4]], axis: 1)  # [3, 7]
  """
  @spec sum(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def sum(data, opts \\ []) do
    call_numpy_tool(
      "np_sum",
      %{
        "data" => data,
        "axis" => Keyword.get(opts, :axis)
      },
      opts
    )
  end

  @doc """
  Compute the dot product of two arrays.

  ## Examples

      Numpy.dot([1, 2], [3, 4])  # 11
      Numpy.dot([[1, 0], [0, 1]], [[4, 1], [2, 2]])  # matrix multiply
  """
  @spec dot(list(), list(), keyword()) :: {:ok, map()} | {:error, term()}
  def dot(a, b, opts \\ []) do
    call_numpy_tool(
      "np_dot",
      %{
        "a" => a,
        "b" => b
      },
      opts
    )
  end

  @doc """
  Reshape an array to a new shape.

  ## Examples

      Numpy.reshape([1, 2, 3, 4, 5, 6], [2, 3])
      # [[1, 2, 3], [4, 5, 6]]
  """
  @spec reshape(list(), list(integer()), keyword()) :: {:ok, map()} | {:error, term()}
  def reshape(data, shape, opts \\ []) do
    call_numpy_tool(
      "np_reshape",
      %{
        "data" => data,
        "shape" => shape
      },
      opts
    )
  end

  @doc """
  Transpose an array.

  ## Examples

      Numpy.transpose([[1, 2], [3, 4]])
      # [[1, 3], [2, 4]]
  """
  @spec transpose(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def transpose(data, opts \\ []) do
    call_numpy_tool(
      "np_transpose",
      %{
        "data" => data,
        "axes" => Keyword.get(opts, :axes)
      },
      opts
    )
  end

  # Private helpers

  defp call_numpy_tool(tool_name, args, opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    result = Runtime.execute_with_timeout(session_id, tool_name, args, timeout: timeout)

    case result do
      {:ok, %{"success" => true} = response} ->
        {:ok, normalize_response(response)}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, _} = error ->
        error
    end
  end

  defp normalize_response(response) do
    response
    |> Map.drop(["success"])
    |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp generate_session_id do
    unique = System.unique_integer([:positive, :monotonic])
    "numpy_session_#{unique}"
  end
end
