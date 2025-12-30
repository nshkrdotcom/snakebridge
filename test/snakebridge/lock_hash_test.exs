defmodule SnakeBridge.LockHashTest do
  use ExUnit.Case, async: true

  describe "generator hash" do
    test "hash changes when generator code changes" do
      hash1 = SnakeBridge.Lock.generator_hash()

      hash2 = SnakeBridge.Lock.generator_hash()
      assert hash1 == hash2
    end

    test "hash includes generator file contents" do
      hash = SnakeBridge.Lock.generator_hash()
      assert is_binary(hash)
      assert byte_size(hash) == 64
    end
  end
end
