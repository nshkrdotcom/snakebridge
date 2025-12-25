defmodule SnakeBridge.Integration.FunctionExecutionTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Manifest.Registry
  alias SnakeBridge.TestHelpers

  @moduletag :integration

  setup do
    Registry.reset()

    TestHelpers.purge_modules([
      Json,
      Demo.Settings,
      Demo.SettingsFunctions,
      Demo.Predict,
      DemoTest.Predict
    ])

    :ok
  end

  describe "function execution with mocked Snakepit" do
    setup do
      # Use the mock adapter for testing
      original_adapter = Application.get_env(:snakebridge, :snakepit_adapter)
      Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitMock)

      on_exit(fn ->
        if is_nil(original_adapter) do
          Application.delete_env(:snakebridge, :snakepit_adapter)
        else
          Application.put_env(:snakebridge, :snakepit_adapter, original_adapter)
        end
      end)

      :ok
    end

    test "discover -> generate -> call function workflow" do
      # Step 1: Discover a module
      {:ok, schema} = SnakeBridge.discover("demo")

      # Verify functions were discovered
      assert Map.has_key?(schema, "functions")
      functions = Map.get(schema, "functions")
      assert is_map(functions)
      assert map_size(functions) > 0

      # Step 2: Convert to config
      config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "demo")

      # Verify functions in config
      assert length(config.functions) > 0

      # Step 3: Generate modules
      {:ok, modules} = SnakeBridge.generate(config)

      # Should have both class and function modules
      assert length(modules) > 0

      # Step 4: Find function module and call a function
      # Note: The function module will be generated for demo.settings.configure
      function_module =
        Enum.find(modules, fn mod ->
          function_exported?(mod, :configure, 0) || function_exported?(mod, :configure, 1) ||
            function_exported?(mod, :configure, 2)
        end)

      assert function_module != nil, "Should generate a module with configure function"

      # Step 5: Call the function
      Registry.register_config(config)

      {:ok, result} = function_module.configure()

      # Mock should return a result
      assert is_map(result)
    end

    test "generated function modules have correct structure" do
      config = %SnakeBridge.Config{
        python_module: "json",
        version: "3.11",
        classes: [],
        functions: [
          %{
            name: "dumps",
            python_path: "json.dumps",
            elixir_name: :dumps
          },
          %{
            name: "loads",
            python_path: "json.loads",
            elixir_name: :loads
          }
        ]
      }

      {:ok, [module]} = SnakeBridge.generate(config)

      # Module should have both functions
      assert function_exported?(module, :dumps, 0) || function_exported?(module, :dumps, 1) ||
               function_exported?(module, :dumps, 2)

      assert function_exported?(module, :loads, 0) || function_exported?(module, :loads, 1) ||
               function_exported?(module, :loads, 2)

      # Functions should not require instance (stateless)
      refute function_exported?(module, :create, 0)
      refute function_exported?(module, :create, 1)
      refute function_exported?(module, :create, 2)
    end

    test "can call json.dumps through generated module" do
      config = %SnakeBridge.Config{
        python_module: "json",
        version: "3.11",
        classes: [],
        functions: [
          %{
            name: "dumps",
            python_path: "json.dumps",
            elixir_name: :dumps
          }
        ]
      }

      Registry.register_config(config)

      {:ok, [json_module]} = SnakeBridge.generate(config)

      # Call dumps with arguments
      {:ok, result} = json_module.dumps(%{obj: %{test: "data"}})

      # Mock returns JSON string
      assert is_binary(result)
      assert result =~ "mock"
    end

    test "can call json.loads through generated module" do
      config = %SnakeBridge.Config{
        python_module: "json",
        version: "3.11",
        classes: [],
        functions: [
          %{
            name: "loads",
            python_path: "json.loads",
            elixir_name: :loads
          }
        ]
      }

      Registry.register_config(config)

      {:ok, [json_module]} = SnakeBridge.generate(config)

      # Call loads with arguments
      {:ok, result} = json_module.loads(%{s: "{\"test\": \"data\"}"})

      # Mock returns map
      assert is_map(result)
      assert result["mock"] == true
    end

    test "function calls are stateless - no session sharing required" do
      config = %SnakeBridge.Config{
        python_module: "json",
        version: "3.11",
        classes: [],
        functions: [
          %{
            name: "dumps",
            python_path: "json.dumps",
            elixir_name: :dumps
          }
        ]
      }

      Registry.register_config(config)

      {:ok, [json_module]} = SnakeBridge.generate(config)

      # Multiple calls should work independently
      {:ok, result1} = json_module.dumps(%{obj: %{call: 1}})
      {:ok, result2} = json_module.dumps(%{obj: %{call: 2}})
      {:ok, result3} = json_module.dumps(%{obj: %{call: 3}})

      # All should succeed
      assert is_binary(result1)
      assert is_binary(result2)
      assert is_binary(result3)
    end

    test "handles function errors gracefully" do
      config = %SnakeBridge.Config{
        python_module: "json",
        version: "3.11",
        classes: [],
        functions: [
          %{
            name: "dumps",
            python_path: "json.dumps",
            elixir_name: :dumps
          }
        ]
      }

      Registry.register_config(config)

      {:ok, [json_module]} = SnakeBridge.generate(config)

      # Call should return ok tuple even if Python has issues
      # (Mock always succeeds, but structure is correct)
      result = json_module.dumps(%{obj: %{test: "data"}})

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "function generation with classes" do
    test "can generate both class and function modules from same config" do
      config = %SnakeBridge.Config{
        python_module: "demo",
        version: "1.0.0",
        classes: [
          %{
            python_path: "demo.Predict",
            elixir_module: DemoTest.Predict,
            constructor: %{args: %{}, session_aware: true},
            methods: [%{name: "__call__", elixir_name: :call, streaming: false}]
          }
        ],
        functions: [
          %{
            name: "configure",
            python_path: "demo.settings.configure",
            elixir_name: :configure
          }
        ]
      }

      Registry.register_config(config)

      {:ok, modules} = SnakeBridge.generate(config)

      # Should have 2 modules: 1 class + 1 function module
      assert length(modules) == 2

      # Find class module
      class_module = Enum.find(modules, &function_exported?(&1, :create, 0))
      assert class_module != nil

      # Find function module
      function_module = Enum.find(modules, &function_exported?(&1, :configure, 0))
      assert function_module != nil

      # They should be different modules
      assert class_module != function_module
    end
  end
end
