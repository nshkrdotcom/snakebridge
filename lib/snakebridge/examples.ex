defmodule SnakeBridge.Examples do
  @moduledoc """
  Helpers for SnakeBridge example projects.

  Provides failure tracking to hard-fail on unexpected errors in demo scripts,
  and telemetry-based dispatch monitoring to deterministically wait for pool
  dispatch events instead of using `Process.sleep`.
  """

  @failure_key :snakebridge_example_failures

  @doc """
  Resets the per-process failure counter to zero.
  """
  @spec reset_failures() :: :ok
  def reset_failures do
    Process.put(@failure_key, 0)
    :ok
  end

  @doc """
  Increments the per-process failure counter by one.
  """
  @spec record_failure() :: :ok
  def record_failure do
    Process.put(@failure_key, failure_count() + 1)
    :ok
  end

  @doc """
  Returns the current per-process failure count.
  """
  @spec failure_count() :: non_neg_integer()
  def failure_count do
    Process.get(@failure_key, 0)
  end

  @doc """
  Raises if any failures were recorded in the current process.
  """
  @spec assert_no_failures!() :: :ok
  def assert_no_failures! do
    count = failure_count()

    if count > 0 do
      raise "Example failed with #{count} unexpected error(s)."
    end

    :ok
  end

  @doc """
  Raises if `result` is an `{:error, reason}` tuple.
  """
  @spec assert_script_ok(term()) :: :ok
  def assert_script_ok(result) do
    case result do
      {:error, reason} ->
        raise "Snakepit script failed: #{inspect(reason)}"

      _ ->
        :ok
    end
  end

  @doc """
  Attaches a telemetry handler that forwards `[:snakepit, :pool, :call, :dispatched]`
  events to the calling process as `{:call_dispatched, metadata}` messages.

  Returns the handler ID, which should be passed to `detach_dispatch_monitor/1`
  when monitoring is no longer needed.
  """
  @spec attach_dispatch_monitor(String.t() | nil) :: String.t()
  def attach_dispatch_monitor(handler_id \\ nil) do
    id = handler_id || "dispatch-monitor-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        id,
        [:snakepit, :pool, :call, :dispatched],
        fn _event, _measurements, metadata, config ->
          send(config.pid, {:call_dispatched, metadata})
        end,
        %{pid: parent}
      )

    id
  end

  @doc """
  Detaches a previously attached dispatch monitor by handler ID.
  """
  @spec detach_dispatch_monitor(String.t()) :: :ok | {:error, :not_found}
  def detach_dispatch_monitor(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Waits for a `{:call_dispatched, metadata}` message from an attached dispatch monitor.

  ## Options

    * `:timeout` - maximum wait time in milliseconds (default: `2_000`)
    * `:command` - if set, only matches dispatches for the given command

  Returns the dispatch metadata map, or `nil` on timeout.
  """
  @spec await_dispatch(keyword()) :: map() | nil
  def await_dispatch(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 2_000)
    command = Keyword.get(opts, :command, nil)

    receive do
      {:call_dispatched, metadata} when is_nil(command) ->
        metadata

      {:call_dispatched, %{command: ^command} = metadata} ->
        metadata
    after
      timeout -> nil
    end
  end
end
