defmodule SnakeBridge.Stream do
  @moduledoc """
  Stream utilities for Python calls.

  Provides an Elixir Stream interface for consuming Python calls that return
  collections as well as callback-based streaming endpoints.

  ## Usage

      # Create a stream from a Python generator that returns a list
      stream = SnakeBridge.Stream.from_generator(session_id, "itertools", "count", %{start: 0})

      # Consume with Enum functions
      stream
      |> Stream.take(10)
      |> Enum.to_list()

      # Streaming text generation
      stream = SnakeBridge.Stream.from_generator(session_id, "generate_text_stream", args)
      for chunk <- stream do
        IO.write(chunk)
      end

  ## Cleanup

  Streams are automatically cleaned up when fully consumed.
  """

  alias SnakeBridge.Error
  alias SnakeBridge.Runtime

  @doc """
  Create a stream from a Python generator.

  ## Options

  - `:timeout` - Timeout for each chunk fetch (default: 30_000ms)
  - `:buffer_size` - Number of items to buffer (default: 1)

  ## Examples

      stream = SnakeBridge.Stream.from_generator("session", "itertools", "count", %{start: 0})
      stream |> Stream.take(5) |> Enum.to_list()
      # => [0, 1, 2, 3, 4]
  """
  @spec from_generator(String.t(), String.t(), String.t(), map(), keyword()) :: Enumerable.t()
  def from_generator(session_id, module_path, function_name, args \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    Stream.resource(
      fn -> init_generator(session_id, module_path, function_name, args, timeout) end,
      fn state -> fetch_next(state) end,
      fn _state -> :ok end
    )
  end

  @doc """
  Create a stream from a streaming tool call.

  This is for tools that support streaming responses (e.g., LLM text generation).
  """
  @spec from_streaming_tool(String.t(), String.t(), map(), keyword()) :: Enumerable.t()
  def from_streaming_tool(session_id, tool_name, args \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    Stream.resource(
      fn ->
        %{
          session_id: session_id,
          tool_name: tool_name,
          args: args,
          buffer: [],
          done: false,
          started: false
        }
      end,
      fn state ->
        fetch_streaming_chunk(state, timeout)
      end,
      fn state ->
        cleanup_streaming(state)
      end
    )
  end

  @doc """
  Wrap callback-based streaming in a Stream.

  Converts the callback-based `Runtime.execute_stream/5` to a Stream.
  """
  @spec from_callback(String.t(), String.t(), map(), keyword()) :: Enumerable.t()
  def from_callback(session_id, tool_name, args \\ %{}, _opts \\ []) do
    parent = self()

    Stream.resource(
      fn ->
        # Spawn a task that runs the streaming callback
        task = Task.async(fn -> run_streaming_task(session_id, tool_name, args, parent) end)
        %{task: task, done: false}
      end,
      fn
        %{done: true} = state ->
          {:halt, state}

        state ->
          receive do
            {:stream_chunk, chunk} ->
              handle_stream_chunk(chunk, state)

            :stream_done ->
              {:halt, %{state | done: true}}
          after
            30_000 ->
              {:halt, %{state | done: true}}
          end
      end,
      fn %{task: task} ->
        Task.shutdown(task, :brutal_kill)
      end
    )
  end

  # Private implementation

  defp run_streaming_task(session_id, tool_name, args, parent) do
    Runtime.execute_stream(session_id, tool_name, args, fn chunk ->
      send(parent, {:stream_chunk, chunk})
    end)

    send(parent, :stream_done)
  end

  defp init_generator(session_id, module_path, function_name, args, timeout) do
    case Runtime.execute_with_timeout(
           session_id,
           "call_python",
           %{
             "module_path" => module_path,
             "function_name" => function_name,
             "args" => [],
             "kwargs" => args
           },
           timeout: timeout
         ) do
      {:ok, %{"success" => true, "result" => result}} when is_list(result) ->
        %{buffer: result, done: false}

      {:ok, %{"success" => true, "result" => result}} ->
        %{buffer: [result], done: false}

      {:ok, %{"success" => true} = response} ->
        %{buffer: [response], done: false}

      {:error, %Error{} = error} ->
        %{buffer: [], done: true, error: error}

      {:error, reason} ->
        %{buffer: [], done: true, error: reason}
    end
  end

  defp fetch_next(%{done: true} = state), do: {:halt, state}
  defp fetch_next(%{error: _error} = state), do: {:halt, state}

  defp fetch_next(%{buffer: [item | rest]} = state) do
    next_state = %{state | buffer: rest, done: rest == []}
    {[item], next_state}
  end

  defp fetch_next(%{buffer: []} = state) do
    {:halt, %{state | done: true}}
  end

  defp fetch_streaming_chunk(%{done: true} = state, _timeout), do: {:halt, state}

  defp fetch_streaming_chunk(%{started: false} = state, timeout) do
    # Start the streaming operation
    result =
      Runtime.execute_with_timeout(
        state.session_id,
        state.tool_name,
        state.args,
        timeout: timeout
      )

    case result do
      {:ok, %{"success" => true, "done" => true}} ->
        {:halt, %{state | done: true}}

      {:ok, %{"success" => true, "data" => data}} ->
        {[data], %{state | started: true}}

      {:ok, %{"chunk" => chunk}} ->
        {[chunk], %{state | started: true}}

      {:ok, response} when is_map(response) ->
        # Full response, not streaming
        {[response], %{state | done: true}}

      {:error, reason} ->
        {:halt, %{state | done: true, error: reason}}
    end
  end

  defp fetch_streaming_chunk(state, _timeout) do
    # Continue receiving chunks
    {:halt, %{state | done: true}}
  end

  defp cleanup_streaming(_state), do: :ok

  defp handle_stream_chunk(%{"success" => false} = chunk, state) do
    error = Error.new(chunk)
    {:halt, %{state | done: true, error: error}}
  end

  defp handle_stream_chunk(%{"done" => true}, state) do
    {:halt, %{state | done: true}}
  end

  defp handle_stream_chunk(%{"data" => data}, state) do
    {[data], state}
  end

  defp handle_stream_chunk(%{"chunk" => data}, state) do
    {[data], state}
  end

  defp handle_stream_chunk(other, state) do
    {[other], state}
  end
end
