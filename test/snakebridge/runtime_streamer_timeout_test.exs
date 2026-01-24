defmodule SnakeBridge.RuntimeStreamerTimeoutTest do
  use ExUnit.Case, async: false

  defmodule StreamTimeoutClient do
    @behaviour SnakeBridge.RuntimeClient

    @impl true
    def execute(_tool, _payload, _opts), do: {:ok, :ok}

    @impl true
    def execute_stream(_tool, _payload, _callback, opts) do
      test_pid = Keyword.get(opts, :test_pid)

      if is_pid(test_pid) do
        send(test_pid, {:stream_worker, self()})
      end

      receive do
        :stop -> :ok
      end
    end
  end

  setup do
    assert {:ok, _} = Application.ensure_all_started(:snakebridge)

    previous = Application.get_env(:snakebridge, :runtime_client)
    Application.put_env(:snakebridge, :runtime_client, StreamTimeoutClient)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:snakebridge, :runtime_client)
      else
        Application.put_env(:snakebridge, :runtime_client, previous)
      end
    end)

    :ok
  end

  test "stream_dynamic times out and stops the worker" do
    test_pid = self()

    task =
      Task.async(fn ->
        SnakeBridge.Runtime.stream_dynamic(
          "fake",
          "noop",
          [],
          [__runtime__: [stream_timeout: 50, test_pid: test_pid]],
          fn _chunk -> :ok end
        )
      end)

    assert_receive {:stream_worker, worker_pid}, 500
    assert {:error, :stream_timeout} = Task.await(task, 1000)

    assert SnakeBridge.TestHelpers.eventually(
             fn -> not Process.alive?(worker_pid) end,
             timeout: 500
           )
  end
end
