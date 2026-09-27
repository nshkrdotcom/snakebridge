defmodule SnakeBridge.RuntimeClassMethodTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  defmodule DescriptorDemo do
    def __snakebridge_python_name__, do: "descriptor_fixture"
    def __snakebridge_python_class__, do: "DescriptorDemo"
    def __snakebridge_library__, do: "descriptor_fixture"
  end

  setup do
    restore = SnakeBridge.TestHelpers.put_runtime_client(SnakeBridge.RuntimeClientMock)
    SnakeBridge.Runtime.clear_auto_session()
    on_exit(restore)
    :ok
  end

  test "call_class_method/4 builds class-bound payload without an instance ref" do
    expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
      assert payload["call_type"] == "class_method"
      assert payload["library"] == "descriptor_fixture"
      assert payload["python_module"] == "descriptor_fixture"
      assert payload["class"] == "DescriptorDemo"
      assert payload["function"] == "from_value"
      assert payload["args"] == [4]
      assert payload["kwargs"] == %{"scale" => 3}
      refute Map.has_key?(payload, "instance")
      {:ok, :ok}
    end)

    assert {:ok, :ok} =
             SnakeBridge.Runtime.call_class_method(
               DescriptorDemo,
               :from_value,
               [4],
               scale: 3
             )
  end
end
