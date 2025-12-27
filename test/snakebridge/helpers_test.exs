defmodule SnakeBridge.HelpersTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    original = Application.get_env(:snakebridge, :python_runner)

    on_exit(fn ->
      if original do
        Application.put_env(:snakebridge, :python_runner, original)
      else
        Application.delete_env(:snakebridge, :python_runner)
      end
    end)

    :ok
  end

  test "discover uses the configured python runner" do
    Application.put_env(:snakebridge, :python_runner, SnakeBridge.PythonRunnerMock)

    helper_path = Path.expand("priv/python/helpers")

    config = %SnakeBridge.Config{
      helper_paths: [helper_path],
      helper_pack_enabled: true,
      helper_allowlist: :all
    }

    expect(SnakeBridge.PythonRunnerMock, :run, fn script, args, _opts ->
      assert is_binary(script)
      assert [config_json] = args

      assert %{
               "helper_paths" => [^helper_path],
               "helper_pack_enabled" => true,
               "helper_allowlist" => "all"
             } = Jason.decode!(config_json)

      {:ok, "[{\"name\":\"sympy.parse_implicit\",\"parameters\":[],\"docstring\":\"Parse\"}]"}
    end)

    assert {:ok, [%{"name" => "sympy.parse_implicit"}]} =
             SnakeBridge.Helpers.discover(config)
  end

  test "classifies python errors from helper discovery" do
    Application.put_env(:snakebridge, :python_runner, SnakeBridge.PythonRunnerMock)

    helper_path = Path.expand("priv/python/helpers")

    config = %SnakeBridge.Config{
      helper_paths: [helper_path],
      helper_pack_enabled: true,
      helper_allowlist: :all
    }

    output = "Traceback...\nImportError: helper pack failed"

    expect(SnakeBridge.PythonRunnerMock, :run, fn _script, _args, _opts ->
      {:error, {:python_exit, 1, output}}
    end)

    assert {:error, %SnakeBridge.HelperRegistryError{message: message}} =
             SnakeBridge.Helpers.discover(config)

    assert String.contains?(message, "Helper registry")
  end
end
