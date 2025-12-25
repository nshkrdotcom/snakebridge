defmodule SnakeBridge.Adapter.CodingAgent do
  @moduledoc """
  Abstract coding agent interface for adapter creation.

  Works with both ClaudeAgentSDK and CodexSDK - they're both coding agents
  that can read files, write files, and run commands.
  """

  require Logger

  @type agent_backend :: :claude | :codex
  @type stream_callback :: (String.t() -> :ok)

  @doc """
  Detects which coding agent backends are available.
  """
  @spec available_backends() :: [agent_backend()]
  def available_backends do
    backends = []

    backends = if claude_available?(), do: [:claude | backends], else: backends
    backends = if codex_available?(), do: [:codex | backends], else: backends

    Enum.reverse(backends)
  end

  @doc """
  Returns the best available backend.
  """
  @spec best_backend() :: agent_backend() | nil
  def best_backend do
    List.first(available_backends())
  end

  @doc """
  Runs the adapter creation task using a coding agent.

  The agent will:
  1. Read the library source code
  2. Write the manifest JSON file
  3. Write the Python bridge if needed
  4. Write an example script
  5. Write tests
  6. Run tests and iterate until passing

  ## Options

  - `:backend` - Force :claude or :codex
  - `:on_output` - Callback for streaming output (fn text -> :ok end)
  - `:max_functions` - Max functions to include (default: 15)
  - `:timeout` - Timeout in ms (default: 300_000)
  """
  @spec create_adapter(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_adapter(lib_path, lib_name, opts \\ []) do
    backend = Keyword.get(opts, :backend) || best_backend()
    on_output = Keyword.get(opts, :on_output, &default_output/1)
    max_functions = Keyword.get(opts, :max_functions, 15)

    # Agent works from project root, reads library from lib_path
    project_root = File.cwd!()
    abs_lib_path = Path.expand(lib_path, project_root)

    unless backend do
      {:error, :no_backend_available}
    else
      prompt = build_prompt(abs_lib_path, lib_name, max_functions, project_root)

      on_output.("🚀 Starting #{backend} agent for #{lib_name}...\n")
      on_output.("📁 Library: #{abs_lib_path}\n")
      on_output.("📁 Project: #{project_root}\n\n")

      run_agent(backend, project_root, prompt, on_output, opts)
    end
  end

  # Build the ONE prompt that tells the agent exactly what to do
  defp build_prompt(lib_path, lib_name, max_functions, project_root) do
    """
    # Task: Create SnakeBridge Adapter for #{lib_name}

    Working directory: #{project_root}
    Library source: #{lib_path}

    You are creating a SnakeBridge adapter to integrate the Python library at `#{lib_path}` with Elixir.

    ## What is SnakeBridge?

    SnakeBridge creates Elixir wrappers for Python libraries. It needs:
    1. A JSON manifest defining functions to expose
    2. Optionally, a Python bridge for custom serialization

    ## CRITICAL CONSTRAINTS

    - Only STATELESS functions work (no class instances, no file I/O, no network)
    - Inputs must be JSON-serializable (strings, numbers, lists, maps)
    - Outputs must be JSON-serializable (or need a bridge to convert)
    - AVOID: file ops, GUI, plotting, database, network, threading, eval, pickle

    ## Your Task (Do these steps IN ORDER)

    ### Step 1: Read and Understand
    - Read the README.md to understand what the library does
    - Read the main Python module to find the key functions
    - Identify #{max_functions} best stateless functions to expose

    ### Step 2: Write the Manifest
    Create file: `priv/snakebridge/manifests/#{lib_name}.json`

    The manifest must have this structure:
    ```json
    {
      "name": "#{lib_name}",
      "python_module": "<import name>",
      "python_path_prefix": "<module path or bridges.#{lib_name}_bridge>",
      "version": "<version or null>",
      "category": "<math|text|data|ml|validation|utilities>",
      "elixir_module": "SnakeBridge.<ModuleName>",
      "pypi_package": "<pip package name>",
      "description": "<one line description>",
      "status": "experimental",
      "types": {
        "<arg_name>": "<string|integer|float|boolean|list|map|any>"
      },
      "functions": [
        {
          "name": "<function_name>",
          "args": ["<arg1>", "<arg2>"],
          "returns": "<return_type>",
          "doc": "<brief description>"
        }
      ]
    }
    ```

    ### Step 3: Write Bridge (if needed)
    If any function returns non-JSON-serializable objects, create:
    `priv/python/bridges/#{lib_name}_bridge.py`

    Bridge template:
    ```python
    \"\"\"SnakeBridge bridge for #{lib_name}.\"\"\"
    import <library>

    def <function_name>(<args>):
        result = <library>.<function>(<args>)
        return _serialize(result)

    def _serialize(obj):
        if obj is None:
            return None
        if isinstance(obj, (str, int, float, bool)):
            return obj
        if isinstance(obj, (list, tuple)):
            return [_serialize(x) for x in obj]
        if isinstance(obj, dict):
            return {str(k): _serialize(v) for k, v in obj.items()}
        return str(obj)
    ```

    If using a bridge, set `python_path_prefix` to `bridges.#{lib_name}_bridge` in the manifest.

    ### Step 4: Write Example
    Create file: `examples/manifest_#{lib_name}.exs`

    ```elixir
    # Example usage of SnakeBridge.<ModuleName>
    # Run: mix run examples/manifest_#{lib_name}.exs

    Application.ensure_all_started(:snakebridge)
    Process.sleep(1000)

    alias SnakeBridge.<ModuleName>

    IO.puts("=== #{lib_name} Examples ===")

    # Call the most useful function with example args
    {:ok, result} = <ModuleName>.<function>(%{<args>})
    IO.inspect(result)
    ```

    ### Step 5: Write Test
    Create file: `test/snakebridge/#{lib_name}_test.exs`

    ```elixir
    defmodule SnakeBridge.<ModuleName>Test do
      use ExUnit.Case, async: false
      @moduletag :real_python

      setup_all do
        Application.ensure_all_started(:snakebridge)
        Process.sleep(500)
        :ok
      end

      test "<function_name> works" do
        result = SnakeBridge.<ModuleName>.<function>(%{<args>})
        assert {:ok, _} = result
      end
    end
    ```

    ### Step 6: Validate
    - Run: `mix snakebridge.manifest.validate priv/snakebridge/manifests/#{lib_name}.json`
    - Fix any issues and re-run until it passes

    ## Success Criteria

    1. ✅ Manifest file exists and is valid JSON
    2. ✅ Manifest validates with mix task
    3. ✅ All selected functions are stateless
    4. ✅ Example file is syntactically correct
    5. ✅ Test file is syntactically correct

    ## START NOW

    Begin by reading the README.md at `#{lib_path}/README.md`
    """
  end

  # Run with Claude using Client for streaming messages with tool use
  defp run_agent(:claude, lib_path, prompt, on_output, _opts) do
    alias ClaudeAgentSDK.{Client, ContentExtractor, Message, Options}

    # Show the prompt being sent
    on_output.("\n📝 Prompt sent to agent:\n")
    on_output.(String.duplicate("─", 60) <> "\n")
    on_output.(prompt <> "\n")
    on_output.(String.duplicate("─", 60) <> "\n\n")

    options = %Options{
      model: "sonnet",
      cwd: lib_path
    }

    try do
      {:ok, client} = Client.start_link(options)

      # Start streaming in a task
      task =
        Task.async(fn ->
          Client.stream_messages(client)
          |> Enum.reduce_while({:ok, []}, fn message, {status, acc} ->
            acc = [message | acc]

            case message do
              %Message{type: :assistant} = msg ->
                text = ContentExtractor.extract_text(msg)

                if is_binary(text) and text != "" do
                  on_output.(text <> "\n")
                end

                {:cont, {status, acc}}

              %Message{type: :tool_use} = msg ->
                tool = get_in(msg.data, [:tool]) || get_in(msg.data, ["tool"]) || "unknown"
                on_output.("🔧 Using: #{tool}\n")
                {:cont, {status, acc}}

              %Message{type: :tool_result} ->
                on_output.("📋 Tool completed\n")
                {:cont, {status, acc}}

              %Message{type: :result, subtype: :success} ->
                on_output.("\n✅ Agent finished successfully\n")
                {:halt, {:ok, Enum.reverse(acc)}}

              %Message{type: :result, subtype: subtype} = msg ->
                on_output.("\n❌ Agent finished with: #{subtype}\n")
                error = msg.data[:error]
                if error, do: on_output.("Error: #{error}\n")
                {:halt, {{:error, subtype}, Enum.reverse(acc)}}

              _ ->
                {:cont, {status, acc}}
            end
          end)
        end)

      # Send the message
      :ok = Client.send_message(client, prompt)

      # Wait for completion
      {result_status, _messages} = Task.await(task, 600_000)

      Client.stop(client)

      case result_status do
        :ok -> {:ok, %{backend: :claude}}
        {:error, reason} -> {:error, {:claude_error, reason}}
      end
    rescue
      e -> {:error, {:claude_error, Exception.message(e)}}
    end
  end

  # Run with Codex
  defp run_agent(:codex, lib_path, prompt, on_output, opts) do
    _timeout = Keyword.get(opts, :timeout, 300_000)

    try do
      {:ok, thread} = Codex.start_thread(cwd: lib_path)

      # Run with streaming
      result =
        Codex.Thread.run(thread, prompt, fn event ->
          case event do
            %{type: "message", content: content} when is_binary(content) ->
              on_output.(content)

            %{type: "tool_use", tool: tool} ->
              on_output.("\n🔧 [#{tool}]\n")

            _ ->
              :ok
          end
        end)

      case result do
        {:ok, final} -> {:ok, %{result: final, backend: :codex}}
        {:error, reason} -> {:error, {:codex_error, reason}}
      end
    rescue
      e -> {:error, {:codex_error, Exception.message(e)}}
    end
  end

  defp default_output(text) do
    IO.write(:stdio, text)
    :ok
  end

  defp claude_available? do
    Code.ensure_loaded?(ClaudeAgentSDK) and
      function_exported?(ClaudeAgentSDK, :query, 2)
  end

  defp codex_available? do
    Code.ensure_loaded?(Codex) and
      function_exported?(Codex, :start_thread, 1)
  end
end
