defmodule Demo do
  @moduledoc """
  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Dynamic
  alias SnakeBridge.Examples
  alias SnakeBridge.Runtime
  alias SnakeBridge.SessionContext

  require SnakeBridge

  def run do
    SnakeBridge.script do
      Examples.reset_failures()

      IO.puts("Python Idioms Example")
      IO.puts("---------------------")

      SessionContext.with_session(fn ->
        step("Lazy generators and iterators")
        generator_example()

        step("Context manager support")
        context_manager_example()

        step("Callbacks from Python")
        callback_example()
      end)

      Examples.assert_no_failures!()
    end
    |> Examples.assert_script_ok()
  end

  defp generator_example do
    case Runtime.call_dynamic("itertools", "count", [1]) do
      {:ok, stream_ref} ->
        values = Enum.take(stream_ref, 5)
        IO.puts("Count sample: #{inspect(values)}")

      other ->
        print_result(other)
    end
  end

  defp context_manager_example do
    path = tmp_path()

    case Runtime.call_dynamic("builtins", "open", [path, "w"]) do
      {:ok, ref} ->
        SnakeBridge.with_python ref do
          Dynamic.call(ref, :write, ["hello from snakebridge\n"])
          Dynamic.call(ref, :flush, [])
        end

        print_result(Dynamic.get_attr(ref, :closed))

      other ->
        print_result(other)
    end
  end

  defp callback_example do
    callback = fn value -> value * 2 end

    case Runtime.call_dynamic("builtins", "map", [callback, [1, 2, 3]]) do
      {:ok, stream_ref} ->
        values = Enum.to_list(stream_ref)
        IO.puts("Mapped values: #{inspect(values)}")

      other ->
        print_result(other)
    end
  end

  defp tmp_path do
    filename = "snakebridge_idioms_#{System.unique_integer([:positive])}.txt"
    Path.join(System.tmp_dir!(), filename)
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
