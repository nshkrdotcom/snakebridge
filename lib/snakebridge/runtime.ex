defmodule SnakeBridge.Runtime do
  @moduledoc """
  Runtime execution layer for SnakeBridge.

  Handles interaction with Snakepit, with configurable adapter
  for testing vs production.
  """

  @doc """
  Get the configured Snakepit adapter.

  Returns mock in test, real adapter in dev/prod.
  """
  def snakepit_adapter do
    Application.get_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)
  end

  @doc """
  Execute a tool via Snakepit.
  """
  def execute(session_id, tool_name, args, opts \\ []) do
    adapter = snakepit_adapter()
    adapter.execute_in_session(session_id, tool_name, args, opts)
  end

  @doc """
  Execute a streaming tool via Snakepit.

  The callback function receives each chunk as it arrives.

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
  def execute_stream(session_id, tool_name, args, callback_fn, opts \\ []) do
    Snakepit.execute_in_session_stream(session_id, tool_name, args, callback_fn, opts)
  end

  @doc """
  Create a Python instance.
  """
  @spec create_instance(String.t(), map(), String.t() | nil, keyword()) ::
          {:ok, {String.t(), String.t()}} | {:error, term()}
  def create_instance(python_path, args, session_id, _opts \\ []) do
    session_id = session_id || generate_session_id()
    adapter = snakepit_adapter()

    case adapter.execute_in_session(session_id, "call_python", %{
           "module_path" => python_path,
           "function_name" => "__init__",
           "args" => [],
           "kwargs" => args
         }) do
      {:ok, %{"success" => true, "instance_id" => instance_id}} ->
        {:ok, {session_id, instance_id}}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Call a method on a Python instance.
  """
  @spec call_method({String.t(), String.t()}, String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def call_method({session_id, instance_id}, method_name, args, _opts \\ []) do
    adapter = snakepit_adapter()

    case adapter.execute_in_session(session_id, "call_python", %{
           "module_path" => "instance:#{instance_id}",
           "function_name" => method_name,
           "args" => [],
           "kwargs" => args
         }) do
      {:ok, %{"success" => true, "result" => result}} ->
        {:ok, result}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Call a module-level Python function (not a method on an instance).

  This is for stateless function calls like json.dumps(), numpy.mean(), etc.
  Different from call_method - no instance_id required.
  """
  @spec call_function(String.t(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def call_function(python_path, function_name, args, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    adapter = snakepit_adapter()

    # Extract module path from full python_path (e.g., "json.dumps" -> "json")
    module_path =
      case String.split(python_path, ".") do
        [single] -> single
        parts -> Enum.take(parts, length(parts) - 1) |> Enum.join(".")
      end

    case adapter.execute_in_session(session_id, "call_python", %{
           "module_path" => module_path,
           "function_name" => function_name,
           "args" => [],
           "kwargs" => args
         }) do
      {:ok, %{"success" => true, "result" => result}} ->
        {:ok, result}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_session_id do
    "snakebridge_session_#{:rand.uniform(100_000)}"
  end
end
