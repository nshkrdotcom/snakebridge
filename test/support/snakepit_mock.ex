defmodule SnakeBridge.SnakepitMock do
  @moduledoc """
  Mock implementation of Snakepit for testing.

  Returns canned responses based on tool_name and args.
  No real Python execution - perfect for fast unit tests.
  """

  @behaviour SnakeBridge.SnakepitBehaviour

  @impl true
  def execute_in_session(session_id, tool_name, args, opts \\ [])

  def execute_in_session(_session_id, "describe_library", args, _opts) do
    describe_library_response(args)
  end

  def execute_in_session(_session_id, "call_dspy", args, _opts) do
    call_dspy_response(args)
  end

  def execute_in_session(_session_id, "batch_execute", args, _opts) do
    batch_execute_response(args)
  end

  def execute_in_session(_session_id, tool_name, _args, _opts) do
    {:error, "Unknown tool: #{tool_name}"}
  end

  @impl true
  def get_stats do
    %{
      active_sessions: 0,
      available_workers: 4,
      queued_requests: 0,
      total_executions: 100
    }
  end

  # Private response generators

  defp describe_library_response(%{"module_path" => "dspy"}) do
    {:ok,
     %{
       "success" => true,
       "library_version" => "2.5.0",
       "classes" => %{
         "Predict" => %{
           "name" => "Predict",
           "python_path" => "dspy.Predict",
           "docstring" => "Basic prediction module without intermediate reasoning.",
           "constructor" => %{
             "parameters" => [
               %{
                 "name" => "signature",
                 "type" => %{"kind" => "primitive", "primitive_type" => "str"},
                 "required" => true
               }
             ]
           },
           "methods" => [
             %{
               "name" => "__call__",
               "docstring" => "Execute prediction",
               "parameters" => [],
               "supports_streaming" => false,
               "is_async" => false
             }
           ],
           "properties" => [],
           "base_classes" => []
         }
       },
       "functions" => %{
         "configure" => %{
           "name" => "configure",
           "python_path" => "dspy.settings.configure",
           "docstring" => "Configure global DSPy settings",
           "parameters" => [
             %{"name" => "lm", "required" => false}
           ]
         }
       },
       "descriptor_hash" => "mock_hash_abc123",
       "cache_timestamp" => System.system_time(:second)
     }}
  end

  defp describe_library_response(%{"module_path" => "test_library"}) do
    {:ok,
     %{
       "success" => true,
       "library_version" => "1.0.0",
       "classes" => %{
         "TestClass" => %{
           "name" => "TestClass",
           "python_path" => "test_library.TestClass",
           "docstring" => "A test class for integration testing",
           "constructor" => %{
             "parameters" => [
               %{
                 "name" => "signature",
                 "type" => %{"kind" => "primitive", "primitive_type" => "str"},
                 "required" => true
               }
             ]
           },
           "methods" => [
             %{
               "name" => "execute",
               "docstring" => "Execute test method",
               "parameters" => [],
               "supports_streaming" => false,
               "is_async" => false
             }
           ],
           "properties" => [],
           "base_classes" => []
         }
       },
       "functions" => %{},
       "descriptor_hash" => "mock_hash_test_library"
     }}
  end

  defp describe_library_response(%{"module_path" => module_path})
       when module_path in ["nonexistent", "nonexistent_module"] do
    {:ok,
     %{
       "success" => false,
       "error" => "Module '#{module_path}' not found"
     }}
  end

  defp describe_library_response(%{"module_path" => module_path}) do
    {:ok,
     %{
       "success" => true,
       "library_version" => "1.0.0",
       "classes" => %{},
       "functions" => %{},
       "descriptor_hash" => "mock_hash_#{module_path}"
     }}
  end

  defp call_dspy_response(%{"function_name" => "__init__", "module_path" => module_path}) do
    {:ok,
     %{
       "success" => true,
       "instance_id" => "mock_instance_#{:rand.uniform(10000)}",
       "type" => "constructor",
       "module" => module_path
     }}
  end

  defp call_dspy_response(%{"function_name" => "__call__"}) do
    {:ok,
     %{
       "success" => true,
       "result" => %{
         "answer" => "Mocked answer from DSPy",
         "reasoning" => "Mocked reasoning chain"
       }
     }}
  end

  defp call_dspy_response(%{"function_name" => method_name}) do
    {:ok,
     %{
       "success" => true,
       "result" => %{
         "method" => method_name,
         "mock" => true
       }
     }}
  end

  defp batch_execute_response(%{"operations" => operations}) do
    results =
      Enum.map(operations, fn _op ->
        %{"success" => true, "result" => %{}}
      end)

    {:ok, %{"success" => true, "results" => results}}
  end
end
