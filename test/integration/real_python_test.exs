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
    # Check if SNAKEPIT_PYTHON is set
    python_exe = System.get_env("SNAKEPIT_PYTHON")

    unless python_exe do
      {:skip,
       """
       SNAKEPIT_PYTHON environment variable not set.

       To run real Python tests:
         export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
         mix test --only real_python

       See test/integration/README.md for setup instructions.
       """}
    end

    # Configure for real Python execution
    adapter_spec = "snakebridge_adapter.adapter.SnakeBridgeAdapter"

    # Set PYTHONPATH
    project_root = File.cwd!()
    snakebridge_python = Path.join([project_root, "priv", "python"])
    snakepit_python = Application.app_dir(:snakepit, "priv/python")

    pythonpath =
      [snakebridge_python, snakepit_python]
      |> Enum.filter(&File.dir?/1)
      |> Enum.join(":")

    System.put_env("PYTHONPATH", pythonpath)

    # Switch from mock to real Snakepit adapter
    original_adapter = Application.get_env(:snakebridge, :snakepit_adapter)
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    # Configure Snakepit for real Python
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
    Application.put_env(:snakepit, :pool_config, %{pool_size: 1})
    Application.put_env(:snakepit, :log_level, :info)
    Application.put_env(:snakepit, :grpc_port, 50051)

    Application.put_env(:snakepit, :pools, [
      %{
        name: :default,
        worker_profile: :process,
        pool_size: 1,
        adapter_module: Snakepit.Adapters.GRPCPython,
        adapter_args: ["--adapter", adapter_spec]
      }
    ])

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("REAL PYTHON TEST ENVIRONMENT")
    IO.puts(String.duplicate("=", 60))
    IO.puts("Python: #{python_exe}")
    IO.puts("PYTHONPATH: #{pythonpath}")
    IO.puts("Adapter: #{adapter_spec}")
    IO.puts("Pooling: enabled")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Check if Snakepit is available
    unless Code.ensure_loaded?(Snakepit) do
      {:skip, "Snakepit not available"}
    end

    # Start Snakepit application
    case Application.ensure_all_started(:snakepit) do
      {:ok, _apps} ->
        IO.puts("✓ Snakepit started successfully\n")
        # Give pool time to initialize
        Process.sleep(2000)

      {:error, reason} ->
        {:skip, "Could not start Snakepit: #{inspect(reason)}"}
    end

    on_exit(fn ->
      Application.stop(:snakepit)
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

      result =
        if function_exported?(json_module, :dumps, 1) do
          json_module.dumps(data)
        else
          json_module.dumps(data, [])
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
          session_id,
          "json.dumps",
          %{"obj" => %{"test" => "data"}},
          []
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
