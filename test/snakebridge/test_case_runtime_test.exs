defmodule SnakeBridge.TestCaseRuntimeTest do
  use ExUnit.Case, async: false

  import Mox

  alias SnakeBridge.{Runtime, RuntimeContext, TestCase}

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    restore = SnakeBridge.TestHelpers.put_runtime_client(SnakeBridge.RuntimeClientMock)
    on_exit(restore)

    Runtime.clear_auto_session()
    RuntimeContext.clear_defaults()
    :ok
  end

  test "setup_runtime clears auto session and sets defaults" do
    Process.put(:snakebridge_auto_session, "stale_session")

    :ok = TestCase.setup_runtime(pool: :demo_pool, runtime: [timeout_profile: :ml_inference])

    assert Process.get(:snakebridge_auto_session) == nil
    defaults = RuntimeContext.get_defaults()
    assert Keyword.get(defaults, :pool_name) == :demo_pool
    assert Keyword.get(defaults, :timeout_profile) == :ml_inference
  end

  test "cleanup_runtime releases auto session and clears defaults" do
    stub(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.release_session",
                                                     _payload,
                                                     _opts ->
      {:ok, %{}}
    end)

    Process.put(:snakebridge_auto_session, "auto_test")
    RuntimeContext.put_defaults(pool_name: :demo_pool)

    assert Process.get(:snakebridge_auto_session) == "auto_test"
    assert RuntimeContext.get_defaults() != []

    :ok = TestCase.cleanup_runtime()

    assert Process.get(:snakebridge_auto_session) == nil
    assert RuntimeContext.get_defaults() == []
  end
end
