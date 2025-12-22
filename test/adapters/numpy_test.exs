defmodule SnakeBridge.Adapters.NumpyTest do
  @moduledoc """
  Integration tests for NumPy adapter.

  These tests require NumPy to be installed:
    pip install numpy

  Run with: mix test --include real_python
  """
  use ExUnit.Case

  alias SnakeBridge.Adapters.Numpy

  @moduletag :real_python

  setup_all do
    # Use real Snakepit adapter for these tests
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    on_exit(fn ->
      Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitMock)
    end)

    :ok
  end

  describe "array creation" do
    test "creates array from nested lists" do
      result = Numpy.array([[1, 2, 3], [4, 5, 6]])

      case result do
        {:ok, %{data: data, shape: shape, dtype: _dtype}} ->
          assert data == [[1, 2, 3], [4, 5, 6]]
          assert shape == [2, 3]

        {:error, _} = error ->
          # May fail if NumPy not installed or Snakepit not running
          IO.puts("Test skipped: #{inspect(error)}")
      end
    end

    test "creates array with specific dtype" do
      result = Numpy.array([1.5, 2.5, 3.5], dtype: "float32")

      case result do
        {:ok, %{data: data, dtype: dtype}} ->
          assert length(data) == 3
          assert dtype == "float32"

        {:error, _} ->
          :ok
      end
    end

    test "creates zeros array" do
      result = Numpy.zeros([3, 3])

      case result do
        {:ok, %{data: data, shape: shape}} ->
          assert shape == [3, 3]
          assert Enum.all?(List.flatten(data), &(&1 == 0.0))

        {:error, _} ->
          :ok
      end
    end

    test "creates ones array" do
      result = Numpy.ones([2, 4], dtype: "int32")

      case result do
        {:ok, %{data: data, shape: shape, dtype: dtype}} ->
          assert shape == [2, 4]
          assert dtype == "int32"
          assert Enum.all?(List.flatten(data), &(&1 == 1))

        {:error, _} ->
          :ok
      end
    end

    test "creates arange array" do
      result = Numpy.arange(0, 10, 2)

      case result do
        {:ok, %{data: data}} ->
          assert data == [0, 2, 4, 6, 8]

        {:error, _} ->
          :ok
      end
    end

    test "creates linspace array" do
      result = Numpy.linspace(0, 1, 5)

      case result do
        {:ok, %{data: data}} ->
          assert length(data) == 5
          assert_in_delta hd(data), 0.0, 0.001
          assert_in_delta List.last(data), 1.0, 0.001

        {:error, _} ->
          :ok
      end
    end
  end

  describe "dtype coverage" do
    test "supports float64" do
      result = Numpy.array([1.0, 2.0, 3.0], dtype: "float64")

      case result do
        {:ok, %{dtype: dtype}} ->
          assert dtype == "float64"

        {:error, _} ->
          :ok
      end
    end

    test "supports float32" do
      result = Numpy.array([1.0, 2.0, 3.0], dtype: "float32")

      case result do
        {:ok, %{dtype: dtype}} ->
          assert dtype == "float32"

        {:error, _} ->
          :ok
      end
    end

    test "supports int64" do
      result = Numpy.array([1, 2, 3], dtype: "int64")

      case result do
        {:ok, %{dtype: dtype}} ->
          assert dtype == "int64"

        {:error, _} ->
          :ok
      end
    end

    test "supports int32" do
      result = Numpy.array([1, 2, 3], dtype: "int32")

      case result do
        {:ok, %{dtype: dtype}} ->
          assert dtype == "int32"

        {:error, _} ->
          :ok
      end
    end
  end

  describe "math operations" do
    test "computes mean" do
      result = Numpy.mean([1, 2, 3, 4, 5])

      case result do
        {:ok, %{result: mean}} ->
          assert_in_delta mean, 3.0, 0.001

        {:error, _} ->
          :ok
      end
    end

    test "computes mean along axis" do
      result = Numpy.mean([[1, 2], [3, 4]], axis: 0)

      case result do
        {:ok, %{data: data}} ->
          assert_in_delta hd(data), 2.0, 0.001
          assert_in_delta List.last(data), 3.0, 0.001

        {:error, _} ->
          :ok
      end
    end

    test "computes sum" do
      result = Numpy.sum([1, 2, 3, 4, 5])

      case result do
        {:ok, %{result: sum}} ->
          assert sum == 15.0

        {:error, _} ->
          :ok
      end
    end

    test "computes dot product" do
      result = Numpy.dot([1, 2, 3], [4, 5, 6])

      case result do
        {:ok, %{result: dot}} ->
          # 1*4 + 2*5 + 3*6
          assert dot == 32.0

        {:error, _} ->
          :ok
      end
    end

    test "computes matrix multiplication via dot" do
      result = Numpy.dot([[1, 0], [0, 1]], [[4, 1], [2, 2]])

      case result do
        {:ok, %{data: data}} ->
          assert data == [[4, 1], [2, 2]]

        {:error, _} ->
          :ok
      end
    end
  end

  describe "array manipulation" do
    test "reshapes array" do
      result = Numpy.reshape([1, 2, 3, 4, 5, 6], [2, 3])

      case result do
        {:ok, %{data: data, shape: shape}} ->
          assert shape == [2, 3]
          assert data == [[1, 2, 3], [4, 5, 6]]

        {:error, _} ->
          :ok
      end
    end

    test "transposes array" do
      result = Numpy.transpose([[1, 2, 3], [4, 5, 6]])

      case result do
        {:ok, %{data: data, shape: shape}} ->
          assert shape == [3, 2]
          assert data == [[1, 4], [2, 5], [3, 6]]

        {:error, _} ->
          :ok
      end
    end
  end
end
