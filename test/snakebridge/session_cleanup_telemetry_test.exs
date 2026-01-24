defmodule SnakeBridge.SessionCleanupTelemetryTest do
  use ExUnit.Case, async: false

  defmodule RuntimeClientStub do
    @behaviour SnakeBridge.RuntimeClient

    @impl true
    def execute("snakebridge.release_session", _payload, _opts) do
      {:error, :cleanup_failed}
    end

    def execute(_tool, _payload, _opts), do: {:ok, :ok}

    @impl true
    def execute_stream(_tool, _payload, _callback, _opts), do: :ok
  end

  setup do
    assert {:ok, _} = Application.ensure_all_started(:snakebridge)

    previous = Application.get_env(:snakebridge, :runtime_client)
    Application.put_env(:snakebridge, :runtime_client, RuntimeClientStub)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:snakebridge, :runtime_client)
      else
        Application.put_env(:snakebridge, :runtime_client, previous)
      end
    end)

    :ok
  end

  test "emits cleanup error telemetry when release_session fails" do
    handler_id = "session-cleanup-error-#{System.unique_integer([:positive])}"
    test_pid = self()
    ref = make_ref()

    :telemetry.attach(
      handler_id,
      [:snakebridge, :session, :cleanup, :error],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    session_id = "test_session_#{System.unique_integer([:positive])}"
    :ok = SnakeBridge.SessionManager.register_session(session_id, self())

    :ok = SnakeBridge.SessionManager.release_session(session_id)

    assert_receive {:telemetry_event, ^ref, [:snakebridge, :session, :cleanup, :error],
                    measurements, metadata},
                   1000

    assert is_map(measurements)
    assert metadata.session_id == session_id
    assert metadata.source == :manual
    assert metadata.reason == :cleanup_failed
  end
end
