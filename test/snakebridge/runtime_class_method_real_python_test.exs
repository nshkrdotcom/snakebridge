defmodule SnakeBridge.RuntimeClassMethodRealPythonTest do
  use SnakeBridge.RealPythonCase

  @moduletag :integration
  @moduletag :real_python

  defmodule BuiltinDict do
    def __snakebridge_python_name__, do: "builtins"
    def __snakebridge_python_class__, do: "dict"
    def __snakebridge_library__, do: "builtins"
  end

  defmodule BuiltinStr do
    def __snakebridge_python_name__, do: "builtins"
    def __snakebridge_python_class__, do: "str"
    def __snakebridge_library__, do: "builtins"
  end

  test "dispatches a real Python classmethod through the class object" do
    assert {:ok, %{"a" => 7, "b" => 7}} =
             SnakeBridge.Runtime.call_class_method(
               BuiltinDict,
               :fromkeys,
               [["a", "b"], 7]
             )
  end

  test "dispatches a real Python staticmethod through the class object" do
    assert {:ok, %{97 => 120, 98 => 121}} =
             SnakeBridge.Runtime.call_class_method(
               BuiltinStr,
               :maketrans,
               ["ab", "xy"]
             )
  end
end
