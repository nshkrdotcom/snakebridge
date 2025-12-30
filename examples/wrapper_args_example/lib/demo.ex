defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    Snakepit.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Wrapper Args Example")
      IO.puts("--------------------")

      step("Optional kwargs via opts")
      result = WrapperArgs.mean([[1, 2], [3, 4]], axis: 0)
      print_result(result)

      step("Runtime flags via opts")
      result = WrapperArgs.mean([1, 2, 3], idempotent: true)
      print_result(result)

      step("Varargs via __args__")
      result = WrapperArgs.join_values(__args__: ["snake", "bridge"], sep: "-")
      print_result(result)

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp step(title) do
    IO.puts("")
    IO.puts("== #{title} ==")
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
