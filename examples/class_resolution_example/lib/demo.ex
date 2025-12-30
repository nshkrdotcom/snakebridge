defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    Snakepit.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Class Resolution Example")
      IO.puts("------------------------")

      step("Module constant access (math.pi)")

      if Code.ensure_loaded?(Math) and function_exported?(Math, :pi, 0) do
        print_result(Math.pi())
      else
        missing("Math module not available. Run `mix compile`.")
      end

      step("Stdlib class resolution (pathlib.Path.new/1)")

      if Code.ensure_loaded?(Pathlib.Path) and function_exported?(Pathlib.Path, :new, 1) do
        print_result(Pathlib.Path.new("tmp/snakebridge"))
      else
        missing("Pathlib.Path module not available. Run `mix compile`.")
      end

      maybe_numpy_demo()

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp maybe_numpy_demo do
    numpy = Module.concat([:Numpy])

    if Code.ensure_loaded?(numpy) do
      step("NumPy module constant (numpy.nan)")

      if function_exported?(numpy, :nan, 0) do
        print_result(apply(numpy, :nan, []))
      else
        missing("Numpy.nan/0 not available. Run `mix compile` with numpy enabled.")
      end

      step("NumPy class resolution (numpy.ndarray.shape/1)")

      case apply(numpy, :array, [[1, 2, 3]]) do
        {:ok, ref} ->
          ndarray_module = Module.concat(numpy, "ndarray")

          if Code.ensure_loaded?(ndarray_module) and function_exported?(ndarray_module, :shape, 1) do
            print_result(apply(ndarray_module, :shape, [ref]))
          else
            missing("Numpy.ndarray module not available. Run `mix compile` with numpy enabled.")
          end

        other ->
          print_result(other)
      end
    else
      IO.puts("")
      IO.puts("== NumPy class resolution ==")
      IO.puts("Numpy not configured; set SNAKEBRIDGE_EXAMPLE_NUMPY=1 to enable.")
    end
  end

  defp step(title) do
    IO.puts("")
    IO.puts("== #{title} ==")
  end

  defp missing(message) do
    IO.puts("Result: #{message}")
    Examples.record_failure()
  end

  defp print_result({:ok, value}) do
    IO.puts("Result: {:ok, #{inspect(value)}}")
  end

  defp print_result({:error, reason}) do
    IO.puts("Result: {:error, #{inspect(reason)}}")
    Examples.record_failure()
  end

  defp print_result(other) do
    IO.puts("Result: #{inspect(other)}")
  end
end
