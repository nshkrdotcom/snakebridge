defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    Snakepit.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Strict Mode Example")
      IO.puts("-------------------")
      IO.puts("Strict mode is enabled in config/config.exs")

      step("add/2")
      print_result(StrictModeExample.add(2, 3))

      step("multiply/2")
      print_result(StrictModeExample.multiply(4, 5))

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
