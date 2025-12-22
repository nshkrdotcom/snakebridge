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

    task =
      Task.async(fn ->
        adapter = snakepit_adapter()
        adapter.execute_in_session(session_id, tool_name, args, opts)
      end)

    result =
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {:ok, %{"success" => true} = response}} ->
          {:ok, response}

        {:ok, {:ok, %{"success" => false} = response}} ->
          {:error, Error.new(response)}

        {:ok, {:error, reason}} ->
          {:error, reason}

        {:exit, reason} ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:snakebridge, :call, :exception],
            %{duration: duration},
            %{session_id: session_id, tool_name: tool_name, kind: :exit, reason: reason}
          )

          {:error, reason}

        nil ->
          {:error, Error.from_timeout(timeout)}
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
  Create a Python instance.
  """
  @spec create_instance(String.t(), map(), String.t() | nil, keyword()) ::
          {:ok, {String.t(), String.t()}} | {:error, Error.t() | term()}
  def create_instance(python_path, args, session_id, opts \\ []) do
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

    case result do
      {:ok, response} when is_map(response) ->
        response = normalize_response(response)

        cond do
          match?(%{"success" => true, "instance_id" => _}, response) ->
            {:ok, {session_id, response["instance_id"]}}

          match?(%{"success" => false}, response) ->
            {:error, Error.new(response)}

          true ->
            {:error, {:unexpected_response, response}}
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Call a method on a Python instance.
  """
  @spec call_method({String.t(), String.t()}, String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, Error.t() | term()}
  def call_method({session_id, instance_id}, method_name, args, opts \\ []) do
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

    case result do
      {:ok, response} when is_map(response) ->
        response = normalize_response(response)

        cond do
          match?(%{"success" => true, "result" => _}, response) ->
            {:ok, response["result"]}

          match?(%{"success" => false}, response) ->
            {:error, Error.new(response)}

          true ->
            {:error, {:unexpected_response, response}}
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
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

    # Extract module path from full python_path (e.g., "json.dumps" -> "json")
    module_path =
      case String.split(python_path, ".") do
        [single] -> single
        parts -> Enum.take(parts, length(parts) - 1) |> Enum.join(".")
      end

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

    case result do
      {:ok, response} when is_map(response) ->
        response = normalize_response(response)

        cond do
          match?(%{"success" => true, "result" => _}, response) ->
            {:ok, response["result"]}

          match?(%{"success" => false}, response) ->
            {:error, Error.new(response)}

          true ->
            {:error, {:unexpected_response, response}}
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_session_id do
    "snakebridge_session_#{:rand.uniform(100_000)}"
  end

  defp normalize_args(map) when is_map(map) do
    cond do
      Map.has_key?(map, :__struct__) ->
        map

      true ->
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
end
