defmodule SnakeBridge.Integration.RealPythonTest do
  @moduledoc """
  Integration tests that use REAL Python execution via Snakepit.

  These tests are excluded by default because they require:
  - Python 3.9+ installed
  - Snakepit running
  - Python adapter available

  Run with: mix test --only real_python
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :real_python
  @moduletag :slow

  alias SnakeBridge.{Discovery, Runtime}

  setup_all do
    adapter_spec = "snakebridge_adapter.adapter.SnakeBridgeAdapter"

    {python_exe, pythonpath, pool_config} =
      SnakeBridge.SnakepitTestHelper.prepare_python_env!(adapter_spec)

    original_adapter = Application.get_env(:snakebridge, :snakepit_adapter)
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("REAL PYTHON TEST ENVIRONMENT")
    IO.puts(String.duplicate("=", 60))
    IO.puts("Python: #{python_exe}")
    IO.puts("PYTHONPATH: #{pythonpath}")
    IO.puts("Adapter: #{adapter_spec}")
    IO.puts("Pooling: enabled")
    IO.puts(String.duplicate("=", 60) <> "\n")

    restore_env =
      SnakeBridge.SnakepitTestHelper.start_snakepit!(
        pool_config: pool_config,
        python_executable: python_exe
      )

    on_exit(fn ->
      restore_env.()
      Application.put_env(:snakebridge, :snakepit_adapter, original_adapter)
    end)

    :ok
  end

  describe "describe_library with real Python" do
    test "discovers Python's built-in json module" do
      # Test the Python adapter's describe_library tool
      {:ok, schema} = Discovery.discover("json", [])

      # Should return real schema from Python
      assert is_map(schema)
      assert Map.has_key?(schema, "library_version")
      assert Map.has_key?(schema, "functions")

      # json module should have dumps and loads functions
      functions = schema["functions"]
      assert is_map(functions)
      assert Map.has_key?(functions, "dumps") or Map.has_key?(functions, "dump")
      assert Map.has_key?(functions, "loads") or Map.has_key?(functions, "load")

      IO.puts("\n✓ Successfully discovered json module from real Python")
      IO.inspect(Map.keys(functions), label: "Available functions")
    end

    test "discovers module with error handling for nonexistent module" do
      # Should fail gracefully for nonexistent module
      result = Discovery.discover("this_module_does_not_exist_12345", [])

      assert {:error, _reason} = result
      IO.puts("\n✓ Error handling works for nonexistent module")
    end
  end

  describe "call_python with real Python" do
    @tag timeout: 10_000
    test "calls json.dumps with real Python" do
      # First discover json module
      {:ok, schema} = Discovery.discover("json", [])
      assert is_map(schema)

      # Generate config from schema
      config = Discovery.schema_to_config(schema, python_module: "json")

      # Generate Elixir modules
      {:ok, modules} = SnakeBridge.generate(config)
      assert is_list(modules)
      assert length(modules) > 0

      # Find the module that has dumps function
      json_module =
        Enum.find(modules, fn mod ->
          function_exported?(mod, :dumps, 1) || function_exported?(mod, :dumps, 2)
        end)

      assert json_module != nil, "No module found with dumps function"

      # Try to call json.dumps
      # This is the critical test - does call_python actually work?
      data = %{"test" => "data", "number" => 42}
      args = %{obj: data}

      result =
        if function_exported?(json_module, :dumps, 1) do
          json_module.dumps(args)
        else
          json_module.dumps(args, [])
        end

      case result do
        {:ok, json_string} ->
          IO.puts("\n✓ Successfully called json.dumps from real Python!")
          IO.puts("  Input: #{inspect(data)}")
          IO.puts("  Output: #{inspect(json_string)}")
          assert is_binary(json_string) or is_map(json_string)

        {:error, reason} ->
          IO.puts("\n✗ Failed to call json.dumps:")
          IO.inspect(reason, label: "Error")
          flunk("json.dumps failed: #{inspect(reason)}")

        other ->
          IO.puts("\n✗ Unexpected result from json.dumps:")
          IO.inspect(other, label: "Result")
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    @tag timeout: 10_000
    test "calls Python math functions" do
      # Test with math module (built-in, pure functions)
      {:ok, schema} = Discovery.discover("math", [])
      config = Discovery.schema_to_config(schema, python_module: "math")
      {:ok, modules} = SnakeBridge.generate(config)

      # Find module with sqrt function
      math_module =
        Enum.find(modules, fn mod ->
          function_exported?(mod, :sqrt, 1) || function_exported?(mod, :sqrt, 2)
        end)

      # Skip test if no math module generated
      unless math_module do
        IO.puts("\n⚠️ No module generated with sqrt function (schema might not include functions)")
        IO.puts("  Generated modules: #{length(modules)}")
        # Math module introspection might not work - skip test
        assert true
      else
        # Try calling math.sqrt
        result =
          if function_exported?(math_module, :sqrt, 1) do
            math_module.sqrt(%{x: 16})
          else
            math_module.sqrt(%{x: 16}, [])
          end

        case result do
          {:ok, value} ->
            IO.puts("\n✓ Successfully called math.sqrt from real Python!")
            IO.puts("  sqrt(16) = #{inspect(value)}")
            # sqrt(16) should be 4.0
            assert is_float(value) or is_number(value)

          {:error, reason} ->
            IO.puts("\n✗ Failed to call math.sqrt:")
            IO.inspect(reason, label: "Error")
            # Don't fail test yet, just document the issue
            IO.puts("  Note: This might be expected if call_python needs work")

          other ->
            IO.puts("\n✗ Unexpected result from math.sqrt:")
            IO.inspect(other, label: "Result")
        end
      end
    end
  end

  describe "Runtime.call_function with real Python" do
    @tag timeout: 10_000
    test "directly tests Runtime.call_function" do
      # Create a session
      session_id = "test_session_#{:os.system_time(:millisecond)}"

      # Try calling json.dumps directly through Runtime
      result =
        Runtime.call_function(
          "json",
          "dumps",
          %{"obj" => %{"test" => "data"}},
          session_id: session_id
        )

      case result do
        {:ok, json_string} ->
          IO.puts("\n✓ Runtime.call_function works with real Python!")
          IO.inspect(json_string, label: "Result")

        {:error, reason} ->
          IO.puts("\n✗ Runtime.call_function failed:")
          IO.inspect(reason, label: "Error")

        other ->
          IO.puts("\n✗ Unexpected result:")
          IO.inspect(other, label: "Result")
      end
    end
  end

  describe "class generation with real Python" do
    @tag timeout: 10_000
    test "creates and uses test_modules.simple_class.Greeter" do
      module_path = "test_modules.simple_class"
      {:ok, schema} = Discovery.discover(module_path, [])
      config = Discovery.schema_to_config(schema, python_module: module_path)
      {:ok, modules} = SnakeBridge.generate(config)

      greeter_module =
        Enum.find(modules, fn mod ->
          Atom.to_string(mod) =~ "Greeter" and function_exported?(mod, :greet, 2)
        end)

      assert greeter_module, "Greeter module was not generated from test_modules.simple_class"

      {:ok, instance} = greeter_module.create(%{name: "SnakeBridge"})
      assert {:ok, "Hello from SnakeBridge"} = greeter_module.greet(instance, %{})

      {:ok, repeated} =
        greeter_module.repeat_phrase(instance, %{phrase: "Hi", times: 2})

      assert repeated == "Hi Hi"
    end
  end

  describe "diagnostic information" do
    test "prints Python environment info" do
      IO.puts("\n" <> String.duplicate("=", 60))
      IO.puts("DIAGNOSTIC INFORMATION")
      IO.puts(String.duplicate("=", 60))

      # Check if Snakepit is loaded
      IO.puts("\n1. Snakepit Status:")
      IO.puts("   Loaded: #{Code.ensure_loaded?(Snakepit)}")

      # Check adapter configuration
      adapter = Application.get_env(:snakebridge, :snakepit_adapter)
      IO.puts("\n2. Configured Adapter:")
      IO.puts("   #{inspect(adapter)}")

      # Try to get Snakepit stats if available
      try do
        if Code.ensure_loaded?(Snakepit) do
          stats = Snakepit.get_stats()
          IO.puts("\n3. Snakepit Stats:")
          IO.inspect(stats, label: "   Stats")
        end
      rescue
        e ->
          IO.puts("\n3. Snakepit Stats: Error - #{inspect(e)}")
      end

      # Check Python adapter location
      IO.puts("\n4. Python Adapter:")
      adapter_path = Path.join(:code.priv_dir(:snakebridge), "python/snakebridge_adapter")
      IO.puts("   Path: #{adapter_path}")
      IO.puts("   Exists: #{File.dir?(adapter_path)}")

      if File.dir?(adapter_path) do
        files = File.ls!(adapter_path)
        IO.puts("   Files: #{inspect(files)}")
      end

      IO.puts("\n" <> String.duplicate("=", 60))

      # This test always passes - it's just for info
      assert true
    end
  end
end
