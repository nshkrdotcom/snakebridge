defmodule SnakeBridge.ModuleAttrTest do
  use ExUnit.Case, async: true

  defmodule MathModule do
    def __snakebridge_python_name__, do: "math"
  end

  describe "module attribute access" do
    test "build_module_attr_payload retrieves constant" do
      payload = SnakeBridge.Runtime.build_module_attr_payload(MathModule, :pi)

      assert payload["call_type"] == "module_attr"
      assert payload["python_module"] == "math"
      assert payload["attr"] == "pi"
    end
  end
end
