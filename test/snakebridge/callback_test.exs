defmodule SnakeBridge.CallbackTest do
  use ExUnit.Case, async: true

  setup do
    if Process.whereis(SnakeBridge.CallbackRegistry) == nil do
      start_supervised!(SnakeBridge.CallbackRegistry)
    end

    :ok
  end

  describe "callback encoding" do
    test "function encoded as callback ref" do
      fun = fn x -> x * 2 end
      encoded = SnakeBridge.Types.encode(fun)

      assert encoded["__type__"] == "callback"
      assert is_binary(encoded["ref_id"])
      assert encoded["arity"] == 1
    end
  end

  describe "callback registry" do
    test "registers and invokes callback" do
      fun = fn x -> x + 10 end

      {:ok, callback_id} = SnakeBridge.CallbackRegistry.register(fun, self())

      result = SnakeBridge.CallbackRegistry.invoke(callback_id, [5])
      assert result == {:ok, 15}
    end

    test "cleanup on owner process death" do
      parent = self()
      fun = fn x -> x end

      owner =
        spawn(fn ->
          {:ok, callback_id} = SnakeBridge.CallbackRegistry.register(fun, self())
          send(parent, {:callback_id, callback_id})

          receive do
            :stop -> :ok
          end
        end)

      callback_id =
        receive do
          {:callback_id, id} -> id
        after
          1_000 ->
            flunk("callback id not received")
        end

      ref = Process.monitor(owner)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^ref, :process, ^owner, :killed}, 1000

      # Wait for callback cleanup using eventually
      assert SnakeBridge.TestHelpers.eventually(
               fn ->
                 {:error, :callback_not_found} ==
                   SnakeBridge.CallbackRegistry.invoke(callback_id, [5])
               end,
               timeout: 1000
             )
    end
  end
end
