defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Examples
  alias SnakeBridge.Runtime
  alias SnakeBridge.SessionContext

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Protocol Integration Example")
      IO.puts("----------------------------")

      SessionContext.with_session(fn ->
        step("Inspect and String.Chars")
        inspect_example()

        step("Enumerable over Python refs")
        enumerable_example()

        step("Dynamic exception handling")
        exception_example()
      end)

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp inspect_example do
    case Runtime.call_dynamic("builtins", "range", [0, 5]) do
      {:ok, ref} ->
        IO.puts("Inspect: #{inspect(ref)}")
        IO.puts("Interpolated: #{ref}")

      other ->
        print_result(other)
    end
  end

  defp enumerable_example do
    case Runtime.call_dynamic("builtins", "range", [0, 5]) do
      {:ok, ref} ->
        values = Enum.map(ref, &(&1 * 2))
        count = Enum.count(ref)
        IO.puts("Mapped values: #{inspect(values)}")
        IO.puts("Count: #{count}")

      other ->
        print_result(other)
    end
  end

  defp exception_example do
    with_error_mode(:raise_translated, fn ->
      try do
        Runtime.call_dynamic("builtins", "int", ["not-a-number"])
        IO.puts("Result: expected ValueError")
        Examples.record_failure()
      rescue
        exception ->
          value_error = SnakeBridge.DynamicException.get_or_create_module("ValueError")

          if exception.__struct__ == value_error do
            IO.puts("Caught ValueError: #{Exception.message(exception)}")
          else
            reraise(exception, __STACKTRACE__)
          end
      end
    end)
  end

  defp with_error_mode(mode, fun) when is_function(fun, 0) do
    original = Application.get_env(:snakebridge, :error_mode, :raw)
    Application.put_env(:snakebridge, :error_mode, mode)

    try do
      fun.()
    after
      Application.put_env(:snakebridge, :error_mode, original)
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
