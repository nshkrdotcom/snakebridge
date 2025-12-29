defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  def run do
    Snakepit.run_as_script(fn ->
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
    end)
    |> case do
      {:error, reason} ->
        IO.puts("Snakepit script failed: #{inspect(reason)}")

      _ ->
        :ok
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
  end

  defp print_result(other) do
    IO.puts("Result: #{inspect(other)}")
  end
end
