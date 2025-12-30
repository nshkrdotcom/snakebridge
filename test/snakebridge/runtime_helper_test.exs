defmodule SnakeBridge.RuntimeHelperTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    original_runtime = Application.get_env(:snakebridge, :runtime_client)
    original_helpers = Application.get_env(:snakebridge, :helper_paths)
    original_pack = Application.get_env(:snakebridge, :helper_pack_enabled)
    original_allowlist = Application.get_env(:snakebridge, :helper_allowlist)

    on_exit(fn ->
      if original_runtime do
        Application.put_env(:snakebridge, :runtime_client, original_runtime)
      else
        Application.delete_env(:snakebridge, :runtime_client)
      end

      if is_nil(original_helpers) do
        Application.delete_env(:snakebridge, :helper_paths)
      else
        Application.put_env(:snakebridge, :helper_paths, original_helpers)
      end

      if is_nil(original_pack) do
        Application.delete_env(:snakebridge, :helper_pack_enabled)
      else
        Application.put_env(:snakebridge, :helper_pack_enabled, original_pack)
      end

      if is_nil(original_allowlist) do
        Application.delete_env(:snakebridge, :helper_allowlist)
      else
        Application.put_env(:snakebridge, :helper_allowlist, original_allowlist)
      end
    end)

    :ok
  end

  test "call_helper builds helper payload with config" do
    Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)
    helper_path = Path.expand("priv/python/helpers")
    Application.put_env(:snakebridge, :helper_paths, [helper_path])
    Application.put_env(:snakebridge, :helper_pack_enabled, false)
    Application.put_env(:snakebridge, :helper_allowlist, ["sympy.parse_implicit"])

    expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
      assert payload == %{
               "protocol_version" => 1,
               "min_supported_version" => 1,
               "call_type" => "helper",
               "helper" => "sympy.parse_implicit",
               "function" => "sympy.parse_implicit",
               "library" => "sympy",
               "args" => ["2x"],
               "kwargs" => %{"locale" => "en"},
               "idempotent" => false,
               "helper_config" => %{
                 "helper_paths" => [helper_path],
                 "helper_pack_enabled" => false,
                 "helper_allowlist" => ["sympy.parse_implicit"]
               }
             }

      {:ok, :ok}
    end)

    assert {:ok, :ok} =
             SnakeBridge.Runtime.call_helper("sympy.parse_implicit", ["2x"], locale: "en")
  end

  test "call_helper maps missing helper errors" do
    Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)

    expect(SnakeBridge.RuntimeClientMock, :execute, fn _tool, _payload, _opts ->
      {:error,
       %Snakepit.Error.PythonException{
         message: "Helper 'sympy.parse_implicit' not found",
         python_type: "SnakeBridgeHelperNotFoundError"
       }}
    end)

    assert {:error, %SnakeBridge.HelperNotFoundError{helper: "sympy.parse_implicit"}} =
             SnakeBridge.Runtime.call_helper("sympy.parse_implicit", ["2x"])
  end

  test "call_helper maps non-serializable arguments" do
    Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)

    expect(SnakeBridge.RuntimeClientMock, :execute, fn _tool, _payload, _opts ->
      {:error, {:invalid_parameter, :json_encode_failed, "encode failed"}}
    end)

    assert {:error, %SnakeBridge.SerializationError{}} =
             SnakeBridge.Runtime.call_helper("sympy.parse_implicit", [self()])
  end
end
