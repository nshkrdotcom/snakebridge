defmodule SnakeBridge.SessionContext do
  @moduledoc """
  Provides scoped session context for Python calls.

  Sessions control the lifecycle of Python object references (refs). Each session
  is isolated, meaning refs from one session cannot be used in another.

  ## Automatic vs Explicit Sessions

  By default, SnakeBridge creates an auto-session for each Elixir process. This is
  convenient for most use cases where Python objects don't need to be shared.

  Use explicit sessions when you need:
  - Multiple processes to access the same Python objects
  - Long-lived refs that outlive a single request/task
  - Fine-grained control over cleanup timing

  ## Usage

      # Explicit session with custom ID
      SnakeBridge.SessionContext.with_session([session_id: "my-session"], fn ->
        {:ok, model} = SnakeBridge.call("sklearn.linear_model", "LinearRegression", [])
        # model ref is accessible by other processes using "my-session"
        model
      end)

      # Simple scoped session (auto-generated ID)
      SnakeBridge.SessionContext.with_session(fn ->
        # All Python calls here use the same session
        {:ok, df} = SnakeBridge.call("pandas", "DataFrame", [[1, 2, 3]])
        {:ok, mean} = SnakeBridge.method(df, "mean", [])
        mean
      end)

  ## Session Cleanup

  Sessions are automatically cleaned up when:
  - All owning processes die (auto-sessions)
  - `SnakeBridge.Runtime.release_session/1` is called explicitly
  - Refs exceed TTL (SessionContext default: 1 hour) or max count (default 10,000)

  ## Sharing Refs Across Processes

  To share Python objects across processes, use the same explicit session_id:

      # Process A
      session_id = "shared-#{System.unique_integer()}"
      SessionContext.with_session([session_id: session_id], fn ->
        {:ok, ref} = SnakeBridge.call("heavy_model", "load", [])
        send(process_b, {:model, session_id, ref})
      end)

      # Process B - can use the ref if it adopts the same session
      receive do
        {:model, session_id, ref} ->
          SessionContext.with_session([session_id: session_id], fn ->
            {:ok, result} = SnakeBridge.method(ref, "predict", [data])
            result
          end)
      end

  ## Options

  - `:session_id` - Custom session ID (default: auto-generated)
  - `:max_refs` - Maximum refs per session (default: 10,000)
  - `:ttl_seconds` - Session time-to-live in seconds (default: 3600, i.e., 1 hour)
  - `:tags` - Custom metadata for debugging
  """

  alias Snakepit.Bridge.SessionStore

  @context_key :snakebridge_session_context

  defstruct [
    :session_id,
    :owner_pid,
    :created_at,
    max_refs: 10_000,
    ttl_seconds: 3600,
    tags: %{}
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          owner_pid: pid(),
          created_at: integer(),
          max_refs: pos_integer(),
          ttl_seconds: pos_integer(),
          tags: map()
        }

  @doc """
  Creates a new session context.
  """
  @spec create(keyword()) :: t()
  def create(opts \\ []) do
    default_max_refs = Application.get_env(:snakebridge, :session_max_refs, 10_000)
    default_ttl = Application.get_env(:snakebridge, :session_ttl_seconds, 3600)

    %__MODULE__{
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      owner_pid: Keyword.get(opts, :owner_pid, self()),
      created_at: System.system_time(:second),
      max_refs: Keyword.get(opts, :max_refs, default_max_refs),
      ttl_seconds: Keyword.get(opts, :ttl_seconds, default_ttl),
      tags: Keyword.get(opts, :tags, %{})
    }
  end

  @doc """
  Gets the current session context from the process dictionary.
  """
  @spec current() :: t() | nil
  def current do
    Process.get(@context_key)
  end

  @doc """
  Sets the current session context in the process dictionary.
  """
  @spec put_current(t()) :: t() | nil
  def put_current(context) do
    Process.put(@context_key, context)
  end

  @doc """
  Clears the current session context.
  """
  @spec clear_current() :: t() | nil
  def clear_current do
    Process.delete(@context_key)
  end

  @doc """
  Executes a function within a session context.

  The session is automatically registered and will be released
  when the last owner process dies.
  """
  @spec with_session((-> result)) :: result when result: term()
  def with_session(fun) when is_function(fun, 0) do
    with_session([], fun)
  end

  @spec with_session(keyword(), (-> result)) :: result when result: term()
  def with_session(opts, fun) when is_list(opts) and is_function(fun, 0) do
    context = create(opts)

    :ok = SnakeBridge.SessionManager.register_session(context.session_id, context.owner_pid)

    ensure_snakepit_session(context.session_id)

    old_context = put_current(context)

    try do
      fun.()
    after
      if old_context do
        put_current(old_context)
      else
        clear_current()
      end
    end
  end

  defp generate_session_id do
    "session_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  defp ensure_snakepit_session(session_id) when is_binary(session_id) do
    if Code.ensure_loaded?(SessionStore) and Process.whereis(SessionStore) do
      _ = SessionStore.create_session(session_id)
    end

    :ok
  end
end
