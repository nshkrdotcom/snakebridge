defmodule SnakeBridge.AutoRefTest do
  use ExUnit.Case, async: true

  describe "auto-ref for unknown types" do
    test "decoder handles ref structure" do
      ref_data = %{
        "__type__" => "ref",
        "__schema__" => 1,
        "id" => "abc123",
        "session_id" => "default",
        "python_module" => "pandas",
        "library" => "pandas"
      }

      result = SnakeBridge.Types.decode(ref_data)
      assert %SnakeBridge.Ref{id: "abc123", session_id: "default"} = result
    end

    test "encoder does not stringify refs" do
      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "id" => "test123",
          "session_id" => "default"
        })

      encoded = SnakeBridge.Types.encode(ref)
      assert encoded["__type__"] == "ref"
      assert encoded["id"] == "test123"
      refute is_binary(encoded)
    end
  end
end
