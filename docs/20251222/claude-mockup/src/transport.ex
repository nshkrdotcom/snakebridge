defmodule XTrack.Transport do
  @moduledoc """
  Transport layer for receiving events from Python workers.

  Provides adapters for:
  - Port (stdio to spawned process)
  - TCP server
  - Unix socket server
  - File replay
  """

  # ============================================================================
  # Behaviour
  # ============================================================================

  @doc "Transport behaviour for receiving events"
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback stop(pid :: pid()) :: :ok

  # ============================================================================
  # Port Transport (stdio to child process)
  # ============================================================================

  defmodule Port do
    @moduledoc """
    Transport using Erlang ports to communicate with a spawned Python process.

    This is the primary integration point with snakepit or direct process spawning.
    """

    use GenServer
    require Logger

    alias XTrack.{Wire, Collector}

    defstruct [:port, :run_id, :buffer, :command, :args, :env]

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def stop(pid) do
      GenServer.stop(pid, :normal)
    end

    @impl true
    def init(opts) do
      run_id = Keyword.fetch!(opts, :run_id)
      command = Keyword.fetch!(opts, :command)
      args = Keyword.get(opts, :args, [])
      env = Keyword.get(opts, :env, [])

      # Build environment with XTrack config
      full_env = [
        {~c"XTRACK_TRANSPORT", ~c"stdio"},
        {~c"XTRACK_RUN_ID", String.to_charlist(run_id)}
        | Enum.map(env, fn {k, v} ->
            {String.to_charlist(to_string(k)), String.to_charlist(to_string(v))}
          end)
      ]

      # Spawn the process with a port
      port_opts = [
        :binary,
        :exit_status,
        :use_stdio,
        {:env, full_env},
        {:args, args},
        # Large line buffer for length-prefixed frames
        {:line, 1_000_000}
      ]

      port = Elixir.Port.open({:spawn_executable, command}, port_opts)

      state = %__MODULE__{
        port: port,
        run_id: run_id,
        buffer: <<>>,
        command: command,
        args: args,
        env: env
      }

      {:ok, state}
    end

    @impl true
    def handle_info({port, {:data, data}}, %{port: port} = state) do
      # Accumulate data and try to decode frames
      buffer = state.buffer <> data
      {events, remaining} = decode_all_frames(buffer, [])

      # Push events to collector
      Enum.each(events, fn envelope ->
        Collector.push_event(state.run_id, envelope)
      end)

      {:noreply, %{state | buffer: remaining}}
    end

    def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
      Logger.info("XTrack worker exited with status #{status}")
      {:stop, {:worker_exit, status}, state}
    end

    def handle_info(msg, state) do
      Logger.warning("XTrack.Transport.Port received unexpected message: #{inspect(msg)}")
      {:noreply, state}
    end

    @impl true
    def terminate(_reason, %{port: port}) do
      Elixir.Port.close(port)
      :ok
    end

    defp decode_all_frames(buffer, acc) do
      case Wire.decode_frame(buffer) do
        {:ok, envelope, rest} ->
          decode_all_frames(rest, [envelope | acc])

        {:incomplete, _} ->
          {Enum.reverse(acc), buffer}

        {:error, reason} ->
          Logger.error("Frame decode error: #{inspect(reason)}")
          {Enum.reverse(acc), <<>>}
      end
    end
  end

  # ============================================================================
  # TCP Server Transport
  # ============================================================================

  defmodule TCP do
    @moduledoc """
    TCP server for receiving events from remote workers.

    Useful for distributed training where workers run on different machines.
    """

    use GenServer
    require Logger

    alias XTrack.{Wire, Collector}

    defstruct [:listen_socket, :port, :connections]

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def stop(pid) do
      GenServer.stop(pid, :normal)
    end

    @impl true
    def init(opts) do
      port = Keyword.get(opts, :port, 9999)

      tcp_opts = [
        :binary,
        packet: :raw,
        active: true,
        reuseaddr: true
      ]

      case :gen_tcp.listen(port, tcp_opts) do
        {:ok, socket} ->
          Logger.info("XTrack TCP server listening on port #{port}")
          send(self(), :accept)
          {:ok, %__MODULE__{listen_socket: socket, port: port, connections: %{}}}

        {:error, reason} ->
          {:stop, reason}
      end
    end

    @impl true
    def handle_info(:accept, state) do
      case :gen_tcp.accept(state.listen_socket, 100) do
        {:ok, client} ->
          Logger.debug("XTrack: New TCP connection")
          {:noreply, %{state | connections: Map.put(state.connections, client, <<>>)}}

        {:error, :timeout} ->
          :ok

        {:error, reason} ->
          Logger.error("XTrack TCP accept error: #{inspect(reason)}")
      end

      send(self(), :accept)
      {:noreply, state}
    end

    def handle_info({:tcp, socket, data}, state) do
      buffer = Map.get(state.connections, socket, <<>>) <> data
      {events, remaining} = decode_all_frames(buffer, [])

      # Route events to appropriate collectors
      Enum.each(events, fn envelope ->
        run_id = extract_run_id(envelope)

        if run_id do
          Collector.push_event(run_id, envelope)
        end
      end)

      {:noreply, %{state | connections: Map.put(state.connections, socket, remaining)}}
    end

    def handle_info({:tcp_closed, socket}, state) do
      Logger.debug("XTrack: TCP connection closed")
      {:noreply, %{state | connections: Map.delete(state.connections, socket)}}
    end

    def handle_info({:tcp_error, socket, reason}, state) do
      Logger.warning("XTrack TCP error: #{inspect(reason)}")
      {:noreply, %{state | connections: Map.delete(state.connections, socket)}}
    end

    @impl true
    def terminate(_reason, state) do
      :gen_tcp.close(state.listen_socket)
      Enum.each(state.connections, fn {socket, _} -> :gen_tcp.close(socket) end)
      :ok
    end

    defp decode_all_frames(buffer, acc) do
      case Wire.decode_frame(buffer) do
        {:ok, envelope, rest} -> decode_all_frames(rest, [envelope | acc])
        {:incomplete, _} -> {Enum.reverse(acc), buffer}
        {:error, _} -> {Enum.reverse(acc), <<>>}
      end
    end

    defp extract_run_id(%{payload: %{run_id: run_id}}) when is_binary(run_id), do: run_id
    defp extract_run_id(%{payload: %{run_id: %{id: id}}}), do: id
    defp extract_run_id(_), do: nil
  end

  # ============================================================================
  # File Replay Transport
  # ============================================================================

  defmodule FileReplay do
    @moduledoc """
    Replay events from a file written by FileTransport on Python side.

    Useful for:
    - Offline experiment processing
    - Testing and debugging
    - Migrating data between systems
    """

    alias XTrack.{Wire, Collector}
    require Logger

    @doc "Replay all events from a file to collectors"
    @spec replay(Path.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
    def replay(path, opts \\ []) do
      run_id = Keyword.get(opts, :run_id)
      # :instant | :realtime | {:multiplier, float}
      speed = Keyword.get(opts, :speed, :instant)

      case File.read(path) do
        {:ok, data} ->
          events = decode_all(data, [])

          last_ts = nil

          count =
            Enum.reduce(events, 0, fn envelope, count ->
              # Optionally pace replay
              case speed do
                :instant -> :ok
                :realtime -> maybe_sleep(envelope, last_ts)
                {:multiplier, m} -> maybe_sleep(envelope, last_ts, m)
              end

              # Route to collector
              target_run_id = run_id || extract_run_id(envelope)

              if target_run_id do
                Collector.push_event(target_run_id, envelope)
              end

              count + 1
            end)

          {:ok, count}

        {:error, reason} ->
          {:error, reason}
      end
    end

    @doc "Stream events from a file"
    @spec stream(Path.t()) :: Enumerable.t()
    def stream(path) do
      Stream.resource(
        fn -> File.open!(path, [:read, :binary]) end,
        fn file ->
          case read_frame(file) do
            {:ok, envelope} -> {[envelope], file}
            :eof -> {:halt, file}
            {:error, _} -> {:halt, file}
          end
        end,
        fn file -> File.close(file) end
      )
    end

    defp read_frame(file) do
      case IO.binread(file, 4) do
        :eof ->
          :eof

        {:error, _} = err ->
          err

        <<len::big-unsigned-32>> ->
          case IO.binread(file, len) do
            :eof -> :eof
            {:error, _} = err -> err
            data -> Wire.decode_json(data)
          end
      end
    end

    defp decode_all(<<>>, acc), do: Enum.reverse(acc)

    defp decode_all(data, acc) do
      case Wire.decode_frame(data) do
        {:ok, envelope, rest} -> decode_all(rest, [envelope | acc])
        _ -> Enum.reverse(acc)
      end
    end

    defp maybe_sleep(%{meta: %{timestamp_us: ts}}, last_ts, multiplier \\ 1.0) do
      if last_ts do
        delta_us = ts - last_ts

        if delta_us > 0 do
          sleep_ms = round(delta_us / 1000 / multiplier)
          Process.sleep(sleep_ms)
        end
      end

      ts
    end

    defp extract_run_id(%{payload: %{run_id: run_id}}) when is_binary(run_id), do: run_id
    defp extract_run_id(%{payload: %{run_id: %{id: id}}}), do: id
    defp extract_run_id(_), do: nil
  end
end
