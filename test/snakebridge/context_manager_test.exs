defmodule SnakeBridge.ContextManagerTest do
  use ExUnit.Case, async: true

  import Mox

  require SnakeBridge

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    restore = SnakeBridge.TestHelpers.put_runtime_client(SnakeBridge.RuntimeClientMock)
    on_exit(restore)

    :ok
  end

  describe "with_python macro" do
    test "calls __enter__ and __exit__" do
      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "id" => "ctx123",
          "session_id" => "default"
        })

      enter_payload = SnakeBridge.WithContext.build_enter_payload(ref)
      assert enter_payload["method"] == "__enter__"

      exit_payload = SnakeBridge.WithContext.build_exit_payload(ref, nil)
      assert exit_payload["method"] == "__exit__"
      assert exit_payload["args"] == [nil, nil, nil]
    end

    test "__exit__ called even on exception" do
      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "id" => "ctx123",
          "session_id" => "default",
          "python_module" => "test",
          "library" => "test"
        })

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        assert payload["function"] == "__enter__"
        {:ok, :entered}
      end)

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        assert payload["function"] == "__exit__"
        {:ok, :ok}
      end)

      assert_raise RuntimeError, fn ->
        SnakeBridge.with_python ref do
          raise "boom"
        end
      end
    end
  end
end
