defmodule SnakeBridge.IntrospectorConsolidationTest do
  use ExUnit.Case, async: false

  describe "introspection via Python script" do
    test "uses standalone introspect.py" do
      {:ok, result} = SnakeBridge.Introspector.introspect(:math, [:sqrt])

      assert is_map(result)
      assert Map.has_key?(result, "functions")
    end

    test "handles introspection errors gracefully" do
      {:error, reason} = SnakeBridge.Introspector.introspect(:nonexistent_module_xyz, [:foo])
      assert is_binary(reason) or is_atom(reason) or is_map(reason)
    end
  end
end
