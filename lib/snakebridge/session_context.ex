defmodule SnakeBridge.SessionContext do
  @moduledoc """
  Provides scoped session context for Python calls.

  ## Usage

      SnakeBridge.SessionContext.with_session(fn ->
        # All Python calls here use the same session
        Python.some_function()
        Python.another_function()
      end)
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
    %__MODULE__{
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      owner_pid: Keyword.get(opts, :owner_pid, self()),
      created_at: System.system_time(:second),
      max_refs: Keyword.get(opts, :max_refs, 10_000),
      ttl_seconds: Keyword.get(opts, :ttl_seconds, 3600),
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
  when the owner process dies.
  """
  @spec with_session((-> result)) :: result when result: term()
  def with_session(fun) when is_function(fun, 0) do
    with_session([], fun)
  end

  @spec with_session(keyword(), (-> result)) :: result when result: term()
  def with_session(opts, fun) when is_list(opts) and is_function(fun, 0) do
    context = create(opts)

    case SnakeBridge.SessionManager.register_session(context.session_id, context.owner_pid) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end

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
