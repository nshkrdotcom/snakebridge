defmodule SnakeBridge.Runtime.Streamer do
  @moduledoc false

  alias SnakeBridge.Runtime
  alias SnakeBridge.Runtime.Payload
  alias SnakeBridge.Runtime.SessionResolver
  alias SnakeBridge.Types

  @type module_ref :: module()
  @type function_name :: atom() | String.t()
  @type args :: list()
  @type opts :: keyword()

  @spec stream(module_ref() | String.t(), function_name() | String.t(), args(), opts(), (term() ->
                                                                                           any())) ::
          :ok | {:ok, :done} | {:error, Runtime.error_reason()}
  def stream(module, function, args \\ [], opts \\ [], callback)

  def stream(module, function, args, opts, callback)
      when is_binary(module) and is_function(callback, 1) do
    function_name = to_string(function)
    stream_dynamic(module, function_name, args, opts, callback)
  end

  def stream(module, function, args, opts, callback)
      when is_atom(module) and is_function(callback, 1) do
    {kwargs, idempotent, extra_args, runtime_opts} = Runtime.split_opts(opts)
    encoded_args = Runtime.encode_args(args ++ extra_args)
    encoded_kwargs = Runtime.encode_kwargs(kwargs)
    session_id = SessionResolver.resolve_session_id(runtime_opts)

    payload =
      Payload.base_payload(module, function, encoded_args, encoded_kwargs, idempotent, session_id)
      |> Map.put("session_id", session_id)

    runtime_opts =
      runtime_opts
      |> Runtime.apply_runtime_defaults(payload, :stream)
      |> SessionResolver.ensure_session_opt(session_id)

    metadata = Runtime.call_metadata(payload, module, function, "stream")
    decode_callback = fn chunk -> callback.(Types.decode(chunk)) end

    Runtime.execute_with_telemetry(metadata, fn ->
      Runtime.runtime_client().execute_stream(
        "snakebridge.stream",
        payload,
        decode_callback,
        runtime_opts
      )
    end)
    |> Runtime.apply_error_mode()
  end

  @spec stream_dynamic(String.t(), String.t(), args(), opts(), (term() -> any())) ::
          {:ok, :done} | {:error, term()}
  def stream_dynamic(module_path, function, args, opts, callback)
      when is_binary(module_path) and is_function(callback, 1) do
    {kwargs, idempotent, extra_args, runtime_opts} = Runtime.split_opts(opts)
    encoded_args = Runtime.encode_args(args ++ extra_args)
    encoded_kwargs = Runtime.encode_kwargs(kwargs)
    session_id = SessionResolver.resolve_session_id(runtime_opts)
    library = Payload.library_from_module_path(module_path)

    payload =
      Payload.protocol_payload()
      |> Map.put("call_type", "dynamic_stream")
      |> Map.put("module_path", module_path)
      |> Map.put("library", library)
      |> Map.put("function", to_string(function))
      |> Map.put("args", encoded_args)
      |> Map.put("kwargs", encoded_kwargs)
      |> Map.put("idempotent", idempotent)
      |> Payload.maybe_put_session_id(session_id)

    runtime_opts =
      runtime_opts
      |> Runtime.apply_runtime_defaults(payload, :stream)
      |> SessionResolver.ensure_session_opt(session_id)

    metadata = %{
      module: module_path,
      function: to_string(function),
      library: library,
      python_module: module_path,
      call_type: "dynamic_stream"
    }

    caller = self()
    stream_ref = make_ref()

    chunk_callback = fn chunk -> send(caller, {stream_ref, :chunk, chunk}) end

    {:ok, pid} =
      Task.start(fn ->
        stream_result =
          Runtime.execute_with_telemetry(metadata, fn ->
            Runtime.runtime_client().execute_stream(
              "snakebridge.stream",
              payload,
              chunk_callback,
              runtime_opts
            )
          end)
          |> Runtime.apply_error_mode()

        send(caller, {stream_ref, :done, stream_result})
      end)

    monitor_ref = Process.monitor(pid)
    result = consume_stream_chunks(stream_ref, monitor_ref, callback)

    case result do
      :ok ->
        {:ok, :done}

      {:error, %Snakepit.Error{category: :validation, message: message}} = error ->
        if is_binary(message) and String.contains?(message, "Streaming not supported") do
          stream_dynamic_legacy(module_path, function, args, opts, callback)
        else
          error
        end

      {:error, _} = error ->
        error
    end
  end

  defp stream_iteration_opts(runtime_opts, ref) do
    runtime_opts = List.wrap(runtime_opts)
    session_id = SessionResolver.resolve_session_id(runtime_opts, ref)
    [__runtime__: SessionResolver.ensure_session_opt(runtime_opts, session_id)]
  end

  defp stream_dynamic_legacy(module_path, function, args, opts, callback) do
    {_kwargs, _idempotent, _extra_args, runtime_opts} = Runtime.split_opts(opts)

    case Runtime.call_dynamic(module_path, function, args, opts) do
      {:ok, %SnakeBridge.StreamRef{} = stream_ref} ->
        stream_iterate(stream_ref, callback, stream_iteration_opts(runtime_opts, stream_ref))

      {:ok, %SnakeBridge.Ref{} = ref} ->
        stream_iterate_ref(ref, callback, stream_iteration_opts(runtime_opts, ref))

      {:ok, other} ->
        callback.(other)
        {:ok, :done}

      error ->
        error
    end
  end

  defp decode_stream_chunk(chunk) when is_map(chunk) do
    payload = Map.drop(chunk, ["is_final", "_metadata"])

    cond do
      payload == %{} ->
        :skip

      Map.has_key?(payload, "__type__") ->
        {:ok, Types.decode(payload)}

      Map.has_key?(payload, "data") and map_size(payload) == 1 ->
        {:ok, Types.decode(payload["data"])}

      true ->
        {:ok, Types.decode(payload)}
    end
  end

  defp decode_stream_chunk(chunk), do: {:ok, Types.decode(chunk)}

  defp consume_stream_chunks(stream_ref, monitor_ref, callback) do
    receive do
      {^stream_ref, :chunk, chunk} ->
        case decode_stream_chunk(chunk) do
          :skip -> :ok
          {:ok, value} -> callback.(value)
        end

        consume_stream_chunks(stream_ref, monitor_ref, callback)

      {^stream_ref, :done, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, _pid, reason} ->
        {:error, reason}
    end
  end

  defp stream_iterate(stream_ref, callback, opts) do
    case Runtime.stream_next(stream_ref, opts) do
      {:ok, item} ->
        callback.(item)
        stream_iterate(stream_ref, callback, opts)

      {:error, :stop_iteration} ->
        {:ok, :done}

      {:error, _} = error ->
        error
    end
  end

  defp stream_iterate_ref(ref, callback, opts) do
    case Runtime.call_method(ref, :__iter__, [], opts) do
      {:ok, %SnakeBridge.StreamRef{} = stream_ref} ->
        stream_iterate(stream_ref, callback, opts)

      {:ok, %SnakeBridge.Ref{} = iter_ref} ->
        stream_iterate_ref_next(iter_ref, callback, opts)

      {:ok, other} ->
        callback.(other)
        {:ok, :done}

      {:error, reason} ->
        if stop_iteration?(reason) do
          {:ok, :done}
        else
          stream_iterate_ref_next(ref, callback, opts)
        end
    end
  end

  defp stream_iterate_ref_next(ref, callback, opts) do
    case Runtime.call_method(ref, :__next__, [], opts) do
      {:ok, item} ->
        callback.(item)
        stream_iterate_ref_next(ref, callback, opts)

      {:error, reason} ->
        if stop_iteration?(reason) do
          {:ok, :done}
        else
          {:error, reason}
        end
    end
  end

  defp stop_iteration?(reason) when is_map(reason) do
    type =
      Map.get(reason, :python_type) || Map.get(reason, "python_type") ||
        Map.get(reason, :error_type) || Map.get(reason, "error_type")

    type == "StopIteration"
  end
end
