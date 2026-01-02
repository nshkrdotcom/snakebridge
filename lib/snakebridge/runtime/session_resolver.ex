defmodule SnakeBridge.Runtime.SessionResolver do
  @moduledoc false

  alias SnakeBridge.SessionContext
  alias SnakeBridge.SessionManager

  require Logger

  # Process dictionary key for auto-session
  @auto_session_key :snakebridge_auto_session

  # Session ID single source of truth: determine once, use everywhere
  # Priority: runtime_opts override > ref session_id > context session > auto-session
  @doc false
  def resolve_session_id(runtime_opts, ref \\ nil) do
    session_id_from_runtime_opts(runtime_opts) ||
      session_id_from_ref(ref) ||
      current_session_id()
  end

  @doc false
  def ensure_session_opt(runtime_opts, session_id) when is_binary(session_id) do
    cond do
      runtime_opts == nil ->
        [session_id: session_id]

      is_list(runtime_opts) ->
        Keyword.put_new(runtime_opts, :session_id, session_id)

      true ->
        runtime_opts
    end
  end

  def ensure_session_opt(runtime_opts, _session_id), do: runtime_opts

  @doc false
  def current_session_id do
    case SessionContext.current() do
      %{session_id: session_id} when is_binary(session_id) -> session_id
      _ -> ensure_auto_session()
    end
  end

  @doc """
  Returns the current session ID (explicit or auto-generated).

  This is useful for debugging or when you need to know which session is active.
  """
  @spec current_session() :: String.t()
  def current_session do
    current_session_id()
  end

  @doc """
  Clears the auto-session for the current process.

  Useful for testing or when you want to force a new session.
  Does NOT release the session on the Python side - use `release_auto_session/0` for that.
  """
  @spec clear_auto_session() :: :ok
  def clear_auto_session do
    Process.delete(@auto_session_key)
    :ok
  end

  @doc """
  Releases and clears the auto-session for the current process.

  This releases all refs associated with the session on both Elixir and Python sides.
  """
  @spec release_auto_session() :: :ok
  def release_auto_session do
    case Process.get(@auto_session_key) do
      nil ->
        :ok

      session_id ->
        _ = SnakeBridge.Runtime.release_session(session_id)
        SessionManager.unregister_session(session_id)
        Process.delete(@auto_session_key)
        :ok
    end
  end

  defp session_id_from_runtime_opts(runtime_opts) when is_list(runtime_opts) do
    Keyword.get(runtime_opts, :session_id)
  end

  defp session_id_from_runtime_opts(_), do: nil

  defp session_id_from_ref(%SnakeBridge.Ref{session_id: id}) when is_binary(id), do: id
  defp session_id_from_ref(%SnakeBridge.StreamRef{session_id: id}) when is_binary(id), do: id

  defp session_id_from_ref(ref) when is_map(ref) do
    if Map.has_key?(ref, "session_id") or Map.has_key?(ref, :session_id) do
      ref_field(ref, "session_id")
    end
  end

  defp session_id_from_ref(_), do: nil

  defp ref_field(ref, "session_id") when is_map(ref),
    do: Map.get(ref, "session_id") || Map.get(ref, :session_id)

  defp ref_field(_ref, _key), do: nil

  defp ensure_auto_session do
    case Process.get(@auto_session_key) do
      nil ->
        session_id = generate_auto_session_id()
        setup_auto_session(session_id)
        session_id

      session_id ->
        session_id
    end
  end

  defp generate_auto_session_id do
    pid_string = self() |> :erlang.pid_to_list() |> to_string()
    timestamp = System.system_time(:millisecond)
    "auto_#{pid_string}_#{timestamp}"
  end

  defp setup_auto_session(session_id) do
    Process.put(@auto_session_key, session_id)
    SessionManager.register_session(session_id, self())
    ensure_snakepit_session(session_id)
  end

  defp ensure_snakepit_session(session_id) do
    if Code.ensure_loaded?(Snakepit.SessionStore) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      case apply(Snakepit.SessionStore, :create_session, [session_id]) do
        {:ok, _} ->
          :ok

        {:error, :already_exists} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to create Snakepit session #{session_id}: #{inspect(reason)}")
          :ok
      end
    else
      :ok
    end
  end
end
