defmodule Demo do
  require SnakeBridge

  @moduledoc """
  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    SnakeBridge.script do
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

      step("NumPy module constant (numpy.nan)")
      print_result(Numpy.nan())

      step("NumPy class resolution (numpy.ndarray.shape/1)")

      case Numpy.array([1, 2, 3]) do
        {:ok, ref} -> print_result(Numpy.Ndarray.shape(ref))
        other -> print_result(other)
      end

      Examples.assert_no_failures!()
    end
    |> Examples.assert_script_ok()
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
