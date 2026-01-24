defmodule SnakeBridge.CacheOwnerTest do
  use ExUnit.Case, async: false

  setup do
    assert {:ok, _} = Application.ensure_all_started(:snakebridge)
    :ok
  end

  test "cache tables are owned by CacheOwner and survive caller exit" do
    cache_owner = Process.whereis(SnakeBridge.CacheOwner)
    assert is_pid(cache_owner)

    assert :ets.info(:snakebridge_docs, :owner) == cache_owner
    assert :ets.info(:snakebridge_exception_cache, :owner) == cache_owner

    key = {__MODULE__, :doc}

    inserter =
      spawn(fn ->
        :ets.insert(:snakebridge_docs, {key, "doc"})
      end)

    ref = Process.monitor(inserter)
    assert_receive {:DOWN, ^ref, :process, ^inserter, _reason}, 1000

    assert [{^key, "doc"}] = :ets.lookup(:snakebridge_docs, key)
  end
end
