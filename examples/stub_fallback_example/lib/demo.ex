defmodule Demo do
  @moduledoc """
  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Stub Fallback Example")
      IO.puts("---------------------")

      step("Call function resolved from stub")
      print_result(StubFallbackExample.stubbed(10, 5))

      step("Show stub doc summary")

      case Enum.find(StubFallbackExample.__functions__(), fn {name, _arity, _mod, _summary} ->
             name == :stubbed
           end) do
        nil ->
          IO.puts("Missing stub summary")
          Examples.record_failure()

        {_name, _arity, _mod, summary} ->
          IO.puts("Summary: #{summary}")
      end

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
