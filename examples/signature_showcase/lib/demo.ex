defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Signature Showcase")
      IO.puts("-------------------")

      step("Optional args via kwargs")
      result = SignatureShowcase.optional_args(10, b: 20, c: 30)
      print_result(result)

      step("Keyword-only required")
      result = SignatureShowcase.keyword_only("value", required_kw: "ok")
      print_result(result)

      step("Variadic fallback (signature unavailable)")
      result = SignatureShowcase.variadic(1, 2, three: 3)
      print_result(result)

      step("Sanitized function name")
      result = SignatureShowcase.py_class()
      print_result(result)

      step("C-extension call (math.sqrt)")
      result = Math.sqrt(16)
      print_result(result)

      maybe_numpy_call()

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp maybe_numpy_call do
    numpy = Module.concat([:Numpy])

    if Code.ensure_loaded?(numpy) and function_exported?(numpy, :sqrt, 1) do
      step("C-extension call (numpy.sqrt)")
      result = apply(numpy, :sqrt, [16])
      print_result(result)
    else
      IO.puts("")
      IO.puts("== C-extension call (numpy.sqrt) ==")
      IO.puts("Numpy not configured; set SNAKEBRIDGE_EXAMPLE_NUMPY=1 to enable.")
    end
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
