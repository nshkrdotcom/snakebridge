defmodule SnakeBridge.RegistryIntegrationTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.{Config, Generator, Registry}

  setup do
    Registry.clear()

    on_exit(fn ->
      Registry.clear()
    end)

    :ok
  end

  describe "registry population during compile" do
    test "generate_library registers entry" do
      tmp_dir = Path.join(System.tmp_dir!(), "snakebridge_registry_#{System.unique_integer()}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      library = %Config.Library{
        name: :test_lib,
        python_name: "test_lib",
        module_name: TestLib,
        version: "0.1.0"
      }

      functions = [
        %{
          "name" => "ping",
          "python_name" => "ping",
          "parameters" => [],
          "return_type" => %{"type" => "string"},
          "signature_available" => true
        }
      ]

      config = %Config{generated_dir: tmp_dir}

      Generator.generate_library(library, functions, [], config)

      entry = Registry.get("test_lib")
      assert entry != nil
      assert entry.python_module == "test_lib"
      assert entry.elixir_module == "TestLib"
      assert entry.path == tmp_dir
      assert entry.stats.functions == 1
      assert entry.stats.classes == 0
    end
  end
end
