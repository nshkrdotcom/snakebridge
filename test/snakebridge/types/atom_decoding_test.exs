defmodule SnakeBridge.Types.AtomDecodingTest do
  use ExUnit.Case, async: true

  describe "atom encoding for Python" do
    test "atoms encode with tagged format" do
      encoded = SnakeBridge.Types.encode(:cuda)
      assert encoded["__type__"] == "atom"
      assert encoded["value"] == "cuda"
    end
  end
end
