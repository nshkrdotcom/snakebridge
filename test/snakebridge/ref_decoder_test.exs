defmodule SnakeBridge.RefDecoderTest do
  use ExUnit.Case, async: true

  describe "ref decoding" do
    test "decodes ref type correctly" do
      ref_data = %{
        "__type__" => "ref",
        "__schema__" => 1,
        "id" => "abc123",
        "session_id" => "default",
        "python_module" => "numpy",
        "library" => "numpy"
      }

      result = SnakeBridge.Types.decode(ref_data)

      assert %SnakeBridge.Ref{id: "abc123", session_id: "default"} = result
    end
  end
end
