defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Dynamic
  alias SnakeBridge.Examples
  alias SnakeBridge.Runtime

  def run do
    Snakepit.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Dynamic Dispatch Example")
      IO.puts("------------------------")

      step("Call Python function without generated wrappers")
      print_result(Runtime.call_dynamic("math", "sqrt", [144]))

      step("Create object dynamically and call method")

      case Runtime.call_dynamic("pathlib", "Path", ["."]) do
        {:ok, ref} ->
          print_result(Dynamic.call(ref, :exists, []))

        other ->
          print_result(other)
      end

      step("Get and set attributes on a dynamic ref")

      case Runtime.call_dynamic("types", "SimpleNamespace", []) do
        {:ok, ref} ->
          print_result(Dynamic.set_attr(ref, :name, "snakebridge"))
          print_result(Dynamic.get_attr(ref, :name))

        other ->
          print_result(other)
      end

      step("Invalid ref error handling")
      expect_invalid_ref_error()

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp step(title) do
    IO.puts("")
    IO.puts("== #{title} ==")
  end

  defp expect_invalid_ref_error do
    try do
      Dynamic.call(%{"id" => "bad"}, :noop, [])
      IO.puts("Result: expected invalid ref error")
      Examples.record_failure()
    rescue
      exception in ArgumentError ->
        IO.puts("Result: {:error, #{Exception.message(exception)}}")
    end
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
