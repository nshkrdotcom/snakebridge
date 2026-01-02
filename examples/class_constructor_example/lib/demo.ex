defmodule Demo do
  @moduledoc """
  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Class Constructor Example")
      IO.puts("-------------------------")

      step("EmptyClass.new/0")
      empty_result = ClassConstructor.EmptyClass.new()
      print_result(empty_result)

      step("Point.new/2")
      point_result = ClassConstructor.Point.new(3, 4)
      print_result(point_result)

      case point_result do
        {:ok, ref} ->
          step("Point.magnitude/1")
          print_result(ClassConstructor.Point.magnitude(ref))

        _ ->
          :ok
      end

      step("Config.new/2")
      config_result = ClassConstructor.Config.new("/tmp/demo", readonly: true)
      print_result(config_result)

      case config_result do
        {:ok, ref} ->
          step("Config.summary/1")
          print_result(ClassConstructor.Config.summary(ref))

        _ ->
          :ok
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
