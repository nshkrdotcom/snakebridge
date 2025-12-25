defmodule SnakeBridge.ManifestRegistryTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Manifest.Registry
  alias SnakeBridge.Runtime

  setup do
    Registry.reset()
    :ok
  end

  test "register_config allows configured functions" do
    config = %SnakeBridge.Config{
      python_module: "json",
      functions: [
        %{name: "dumps", python_path: "json.dumps"}
      ]
    }

    Registry.register_config(config)

    assert Registry.allowed_function?("json", "dumps")
    refute Registry.allowed_function?("json", "loads")
  end

  test "call_function rejects non-allowlisted calls" do
    assert {:error, %SnakeBridge.Error{type: :unauthorized}} =
             Runtime.call_function("json", "dumps", %{obj: %{}})
  end

  test "allow_unsafe bypasses allowlist enforcement" do
    assert {:ok, _} =
             Runtime.call_function("json", "dumps", %{obj: %{}}, allow_unsafe: true)
  end
end
