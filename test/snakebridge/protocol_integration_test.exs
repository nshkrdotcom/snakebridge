defmodule SnakeBridge.ProtocolIntegrationTest do
  use ExUnit.Case, async: true

  defp build_ref do
    SnakeBridge.Ref.from_wire_format(%{
      "__type__" => "ref",
      "__schema__" => 1,
      "id" => "test123",
      "session_id" => "default",
      "python_module" => "test",
      "library" => "test"
    })
  end

  describe "Inspect protocol" do
    test "Inspect implementation exists for refs" do
      ref = build_ref()
      assert Inspect.impl_for(ref) == Inspect.SnakeBridge.Ref
    end
  end

  describe "String.Chars protocol" do
    test "String.Chars implementation exists for refs" do
      ref = build_ref()
      assert String.Chars.impl_for(ref) == String.Chars.SnakeBridge.Ref
    end
  end

  describe "Enumerable protocol for refs" do
    test "Enumerable implementation exists for refs" do
      ref = build_ref()
      assert Enumerable.impl_for(ref) == Enumerable.SnakeBridge.Ref
    end
  end
end
