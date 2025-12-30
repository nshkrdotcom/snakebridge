defmodule SnakeBridge.SessionContextTest do
  use ExUnit.Case

  describe "session context" do
    test "creates context with unique session_id" do
      context = SnakeBridge.SessionContext.create()
      assert is_binary(context.session_id)
      assert context.owner_pid == self()
    end

    test "with_session scopes calls to session" do
      result =
        SnakeBridge.SessionContext.with_session(fn ->
          context = SnakeBridge.SessionContext.current()
          assert context != nil
          assert context.owner_pid == self()
          :ok
        end)

      assert result == :ok
    end

    test "context cleaned up after block" do
      SnakeBridge.SessionContext.with_session(fn ->
        assert SnakeBridge.SessionContext.current() != nil
      end)

      assert SnakeBridge.SessionContext.current() == nil
    end
  end
end
