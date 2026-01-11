defmodule Demo do
  @moduledoc """
  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Streaming Example")
      IO.puts("-----------------")

      step("generate/1 (non-streaming)")
      result = Streaming.generate("hello", [])
      print_result(result)

      step("generate_stream/3 (stream: true)")

      callback = fn chunk ->
        IO.puts("Chunk: #{inspect(chunk)}")
        :ok
      end

      stream_result =
        Streaming.generate_stream("hello", [stream: true, count: 3, delay: 0.01], callback)

      print_stream_result(stream_result)

      step("generate_stream/3 with runtime opts")

      stream_result =
        Streaming.generate_stream(
          "hi",
          [stream: true, count: 2, __runtime__: [timeout: 30_000]],
          callback
        )

      print_stream_result(stream_result)

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

  defp print_stream_result(:ok) do
    IO.puts("Stream result: :ok")
  end

  defp print_stream_result({:error, reason}) do
    IO.puts("Stream result: {:error, #{inspect(reason)}}")
    Examples.record_failure()
  end

  defp print_stream_result(other) do
    IO.puts("Stream result: #{inspect(other)}")
  end
end
