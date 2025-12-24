defmodule SnakeBridge.Runtime do
  @moduledoc """
  Runtime execution layer for SnakeBridge.

  Handles interaction with Snakepit, with configurable adapter
  for testing vs production. Includes timeout handling, error
  classification, and telemetry events.

  ## Telemetry Events

  This module emits the following telemetry events:

  - `[:snakebridge, :call, :start]` - Emitted when a call begins
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{session_id: string, tool_name: string}`

  - `[:snakebridge, :call, :stop]` - Emitted when a call completes
    - Measurements: `%{duration: integer}` (in native units)
    - Metadata: `%{session_id: string, tool_name: string, result: :ok | :error}`

  - `[:snakebridge, :call, :exception]` - Emitted on exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{session_id: string, tool_name: string, kind: atom, reason: term}`
  """

  alias SnakeBridge.Error
  alias SnakeBridge.Manifest.Registry

  @default_timeout 30_000

  @doc """
  Get the configured Snakepit adapter.

  Returns mock in test, real adapter in dev/prod.
  """
  def snakepit_adapter do
    Application.get_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)
  end

  @doc """
  Execute a tool via Snakepit with telemetry.
  """
  def execute(session_id, tool_name, args, opts \\ []) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:snakebridge, :call, :start],
      %{system_time: System.system_time()},
      %{session_id: session_id, tool_name: tool_name}
    )

    adapter = snakepit_adapter()
    result = adapter.execute_in_session(session_id, tool_name, args, opts)

    duration = System.monotonic_time() - start_time
    result_status = if match?({:ok, _}, result), do: :ok, else: :error

    :telemetry.execute(
      [:snakebridge, :call, :stop],
      %{duration: duration},
      %{session_id: session_id, tool_name: tool_name, result: result_status}
    )

    result
  end

  @doc """
  Execute a tool with timeout handling.

  Returns `{:error, %SnakeBridge.Error{type: :timeout}}` if the operation
  exceeds the configured timeout.

  ## Options

  - `:timeout` - Timeout in milliseconds (default: #{@default_timeout})

  ## Examples

      Runtime.execute_with_timeout("session", "call_python", %{...}, timeout: 5000)
  """
  @spec execute_with_timeout(String.t(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, Error.t() | term()}
  def execute_with_timeout(session_id, tool_name, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:snakebridge, :call, :start],
      %{system_time: System.system_time()},
      %{session_id: session_id, tool_name: tool_name}
    )

    adapter = snakepit_adapter()

    result =
      adapter.execute_in_session(
        session_id,
        tool_name,
        args,
        Keyword.put(opts, :timeout, timeout)
      )

    result =
      case result do
        {:ok, %{"success" => true} = response} ->
          {:ok, response}

        {:ok, %{"success" => false} = response} ->
          {:error, Error.new(response)}

        {:error, :worker_timeout} ->
          {:error, Error.from_timeout(timeout)}

        {:error, %Snakepit.Error{category: :timeout}} ->
          {:error, Error.from_timeout(timeout)}

        {:error, reason} ->
          {:error, reason}
      end

    duration = System.monotonic_time() - start_time
    result_status = if match?({:ok, _}, result), do: :ok, else: :error

    :telemetry.execute(
      [:snakebridge, :call, :stop],
      %{duration: duration},
      %{session_id: session_id, tool_name: tool_name, result: result_status}
    )

    result
  end

  @doc """
  Execute a streaming tool via the configured adapter.

  The callback function receives each chunk as it arrives.

  ## Options

  - `:timeout` - Timeout in milliseconds (default: #{@default_timeout})

  ## Example

      SnakeBridge.Runtime.execute_stream(
        session_id,
        "generate_text_stream",
        %{"model" => "gemini-2.0-flash-exp", "prompt" => "Hello"},
        fn chunk ->
          IO.write(chunk["chunk"])
        end
      )
  """
  @spec execute_stream(String.t(), String.t(), map(), (map() -> any()), keyword()) ::
          :ok | {:error, Error.t() | term()}
  def execute_stream(session_id, tool_name, args, callback_fn, opts \\ []) do
    adapter = snakepit_adapter()
    adapter.execute_in_session_stream(session_id, tool_name, args, callback_fn, opts)
  end

  @doc """
  Build a Stream for a streaming tool call.
  """
  @spec stream_tool(String.t(), String.t(), map(), keyword()) :: Enumerable.t()
  def stream_tool(session_id, tool_name, args, opts) do
    SnakeBridge.Stream.from_callback(session_id, tool_name, normalize_args(args), opts)
  end

  @doc """
  Build a Stream for a tool, generating a session_id if needed.
  """
  @spec stream_tool(String.t(), map(), keyword()) :: Enumerable.t()
  def stream_tool(tool_name, args \\ %{}, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    stream_tool(session_id, tool_name, args, opts)
  end

  @doc """
  Create a Python instance.
  """
  @spec create_instance(String.t(), map(), String.t() | nil, keyword()) ::
          {:ok, {String.t(), String.t()}} | {:error, Error.t() | term()}
  def create_instance(python_path, args, session_id, opts \\ []) do
    with :ok <- ensure_allowed_class(python_path, opts) do
      session_id = session_id || generate_session_id()
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      result =
        execute_with_timeout(
          session_id,
          "call_python",
          %{
            "module_path" => python_path,
            "function_name" => "__init__",
            "args" => [],
            "kwargs" => normalize_args(args)
          },
          timeout: timeout
        )

      handle_create_instance_result(result, session_id)
    end
  end

  @doc """
  Call a method on a Python instance.
  """
  @spec call_method({String.t(), String.t()}, String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, Error.t() | term()}
  def call_method({session_id, instance_id}, method_name, args, opts \\ []) do
    with :ok <- ensure_allowed_method(instance_id, method_name, opts) do
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      result =
        execute_with_timeout(
          session_id,
          "call_python",
          %{
            "module_path" => "instance:#{instance_id}",
            "function_name" => method_name,
            "args" => [],
            "kwargs" => normalize_args(args)
          },
          timeout: timeout
        )

      handle_method_call_result(result)
    end
  end

  @doc """
  Call a module-level Python function (not a method on an instance).

  This is for stateless function calls like json.dumps(), numpy.mean(), etc.
  Different from call_method - no instance_id required.

  ## Options

  - `:session_id` - Use a specific session (default: auto-generated)
  - `:timeout` - Timeout in milliseconds (default: #{@default_timeout})
  """
  @spec call_function(String.t(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, Error.t() | term()}
  def call_function(python_path, function_name, args, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    module_path = extract_module_path(python_path)

    with :ok <- ensure_allowed_function(module_path, function_name, opts) do
      result =
        execute_with_timeout(
          session_id,
          "call_python",
          %{
            "module_path" => module_path,
            "function_name" => function_name,
            "args" => [],
            "kwargs" => normalize_args(args)
          },
          timeout: timeout
        )

      handle_function_call_result(result)
    end
  end

  @doc """
  Release a stored Python instance by instance_id.
  """
  @spec release_instance({String.t(), String.t()} | String.t(), keyword()) ::
          {:ok, boolean()} | {:error, Error.t() | term()}
  def release_instance(instance_id, opts \\ [])

  def release_instance({_, instance_id}, opts),
    do: release_instance(instance_id, opts)

  def release_instance(instance_id, opts) when is_binary(instance_id) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    result =
      execute_with_timeout(
        session_id,
        "release_instance",
        %{"instance_id" => instance_id},
        timeout: timeout
      )

    case result do
      {:ok, %{"success" => true, "released" => released}} ->
        {:ok, released}

      {:ok, %{"success" => false} = response} ->
        {:error, Error.new(response)}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stream a module-level Python function via the streaming adapter.

  This uses the `call_python_stream` tool and yields chunks as they arrive.
  """
  @spec stream_function(String.t(), String.t(), map(), keyword()) :: Enumerable.t()
  def stream_function(python_path, function_name, args, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    module_path =
      case String.split(python_path, ".") do
        [single] -> single
        parts -> Enum.take(parts, length(parts) - 1) |> Enum.join(".")
      end

    tool_args = %{
      "module_path" => module_path,
      "function_name" => function_name,
      "args" => [],
      "kwargs" => normalize_args(args)
    }

    stream_tool(session_id, "call_python_stream", tool_args, opts)
  end

  defp generate_session_id do
    SnakeBridge.SessionId.generate("snakebridge")
  end

  defp allow_unsafe?(opts) do
    Keyword.get(opts, :allow_unsafe, Application.get_env(:snakebridge, :allow_unsafe, false)) ==
      true
  end

  defp return_unauthorized(module_path, function_name) do
    {:error,
     Error.unauthorized("Call not allowlisted", %{
       module_path: module_path,
       function_name: function_name
     })}
  end

  defp ensure_allowed_function(module_path, function_name, opts) do
    if allow_unsafe?(opts) or Registry.allowed_function?(module_path, function_name) do
      :ok
    else
      return_unauthorized(module_path, function_name)
    end
  end

  defp ensure_allowed_class(python_path, opts) do
    if allow_unsafe?(opts) or Registry.allowed_class?(python_path) do
      :ok
    else
      return_unauthorized(python_path, "__init__")
    end
  end

  defp ensure_allowed_method(instance_id, method_name, opts) do
    if allow_unsafe?(opts) do
      :ok
    else
      return_unauthorized("instance:#{instance_id}", method_name)
    end
  end

  defp normalize_args(map) when is_map(map) do
    if Map.has_key?(map, :__struct__) do
      map
    else
      map
      |> Enum.map(fn {key, value} -> {normalize_key(key), normalize_args(value)} end)
      |> Enum.into(%{})
    end
  end

  defp normalize_args(list) when is_list(list) do
    Enum.map(list, &normalize_args/1)
  end

  defp normalize_args(value), do: value

  defp normalize_response(response) when is_map(response) do
    response
    |> stringify_keys()
    |> ensure_success_flag()
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp ensure_success_flag(%{"success" => _} = response), do: response

  defp ensure_success_flag(%{"error" => _} = response) do
    Map.put(response, "success", false)
  end

  defp ensure_success_flag(%{"result" => _} = response) do
    Map.put(response, "success", true)
  end

  defp ensure_success_flag(%{"instance_id" => _} = response) do
    Map.put(response, "success", true)
  end

  defp ensure_success_flag(response) do
    Map.put_new(response, "success", true)
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key

  # Helper to extract module path from full python_path
  defp extract_module_path(python_path) do
    case String.split(python_path, ".") do
      [single] -> single
      parts -> Enum.take(parts, length(parts) - 1) |> Enum.join(".")
    end
  end

  # Helper to handle create_instance result
  defp handle_create_instance_result({:ok, response}, session_id) when is_map(response) do
    response = normalize_response(response)

    cond do
      match?(%{"success" => true, "instance_id" => _}, response) ->
        {:ok, {session_id, response["instance_id"]}}

      match?(%{"success" => false}, response) ->
        {:error, Error.new(response)}

      true ->
        {:error, {:unexpected_response, response}}
    end
  end

  defp handle_create_instance_result({:error, %Error{} = error}, _session_id) do
    {:error, error}
  end

  defp handle_create_instance_result({:error, reason}, _session_id) do
    {:error, reason}
  end

  # Helper to handle method call result
  defp handle_method_call_result({:ok, response}) when is_map(response) do
    response = normalize_response(response)

    cond do
      match?(%{"success" => true, "result" => _}, response) ->
        {:ok, response["result"]}

      match?(%{"success" => false}, response) ->
        {:error, Error.new(response)}

      true ->
        {:error, {:unexpected_response, response}}
    end
  end

  defp handle_method_call_result({:error, %Error{} = error}) do
    {:error, error}
  end

  defp handle_method_call_result({:error, reason}) do
    {:error, reason}
  end

  # Helper to handle function call result
  defp handle_function_call_result({:ok, response}) when is_map(response) do
    response = normalize_response(response)

    cond do
      match?(%{"success" => true, "result" => _}, response) ->
        {:ok, response["result"]}

      match?(%{"success" => false}, response) ->
        {:error, Error.new(response)}

      true ->
        {:error, {:unexpected_response, response}}
    end
  end

  defp handle_function_call_result({:error, %Error{} = error}) do
    {:error, error}
  end

  defp handle_function_call_result({:error, reason}) do
    {:error, reason}
  end
end
