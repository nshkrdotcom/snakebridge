defmodule SnakeBridge.HelperRegistryIntegrationTest do
  @moduledoc """
  Integration tests for helper registry discovery.

  These tests verify that helper_registry_index works with real Python,
  exercising the _import_helper_module code path that loads helper files.
  """
  use ExUnit.Case, async: false

  @moduletag :real_python

  setup do
    # Ensure we use the real Python runner, not mocks
    original = Application.get_env(:snakebridge, :python_runner)

    on_exit(fn ->
      if original do
        Application.put_env(:snakebridge, :python_runner, original)
      else
        Application.delete_env(:snakebridge, :python_runner)
      end
    end)

    # Use the real system runner
    Application.put_env(:snakebridge, :python_runner, SnakeBridge.PythonRunner.System)

    :ok
  end

  describe "helper registry with real Python" do
    test "discover loads helpers from helper pack" do
      config = %SnakeBridge.Config{
        helper_paths: [],
        helper_pack_enabled: true,
        helper_allowlist: :all
      }

      result = SnakeBridge.Helpers.discover(config)

      assert {:ok, helpers} = result
      assert is_list(helpers)
      assert helpers != []

      # Verify helper structure
      first_helper = hd(helpers)
      assert is_binary(first_helper["name"])
      assert is_list(first_helper["parameters"])
    end

    test "discover loads helpers from custom path" do
      helper_path = Path.join(:code.priv_dir(:snakebridge) |> to_string(), "python/helpers")

      config = %SnakeBridge.Config{
        helper_paths: [helper_path],
        helper_pack_enabled: false,
        helper_allowlist: :all
      }

      result = SnakeBridge.Helpers.discover(config)

      assert {:ok, helpers} = result
      assert is_list(helpers)
    end

    test "discover returns graceful_serialization helpers" do
      config = %SnakeBridge.Config{
        helper_paths: [],
        helper_pack_enabled: true,
        helper_allowlist: :all
      }

      {:ok, helpers} = SnakeBridge.Helpers.discover(config)

      helper_names = Enum.map(helpers, & &1["name"])

      assert "graceful_serialization.validation_configs" in helper_names
      assert "graceful_serialization.list_with_pattern" in helper_names
      assert "graceful_serialization.dict_with_pattern" in helper_names
    end
  end
end
