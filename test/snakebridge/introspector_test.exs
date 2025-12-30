defmodule SnakeBridge.IntrospectorTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.IntrospectionError

  test "introspects stdlib functions via Python script" do
    {:ok, result} = SnakeBridge.Introspector.introspect(:math, [:sqrt])

    assert is_map(result)
    assert Enum.any?(result["functions"], fn info -> info["name"] == "sqrt" end)
  end

  test "classifies python errors from the script" do
    assert {:error, %IntrospectionError{type: :package_not_found}} =
             SnakeBridge.Introspector.introspect(:nonexistent_module_xyz, [:mean])
  end
end
