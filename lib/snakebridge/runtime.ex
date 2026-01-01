defmodule SnakeBridge.Runtime do
  @moduledoc """
  Thin payload helper for SnakeBridge that delegates execution to Snakepit.

  This module is compile-time agnostic and focuses on building payloads that
  match the Snakepit Prime runtime contract.
  """

  alias SnakeBridge.SessionManager
  alias SnakeBridge.Types

  require Logger

  @type module_ref :: module()
  @type function_name :: atom() | String.t()
  @type args :: list()
  @type opts :: keyword()

  @protocol_version 1
  @min_supported_version 1

  # Process dictionary key for auto-session
  @auto_session_key :snakebridge_auto_session

  @doc """
  Call a Python function.

  ## Parameters

  - `module` - Either a generated SnakeBridge module atom OR a Python module path string
  - `function` - Function name (atom or string)
  - `args` - Positional arguments (list)
  - `opts` - Options including kwargs, :idempotent, :__runtime__

  ## Examples

      # With generated module
      {:ok, result} = SnakeBridge.Runtime.call(Numpy, :mean, [[1,2,3]])

      # With string module path (dynamic)
      {:ok, result} = SnakeBridge.Runtime.call("numpy", "mean", [[1,2,3]])
      {:ok, result} = SnakeBridge.Runtime.call("math", :sqrt, [16])

  """
  @spec call(module_ref() | String.t(), function_name() | String.t(), args(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def call(module, function, args \\ [], opts \\ [])

  # String module path - delegate to dynamic
  def call(module, function, args, opts) when is_binary(module) do
    function_name = to_string(function)
    call_dynamic(module, function_name, args, opts)
  end

  # Atom module - existing behavior
  def call(module, function, args, opts) when is_atom(module) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)
    # Determine session_id ONCE using correct priority
    session_id = resolve_session_id(runtime_opts)

    payload =
      base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
      |> Map.put("session_id", session_id)

    runtime_opts = ensure_session_opt(runtime_opts, session_id)
    metadata = call_metadata(payload, module, function, "function")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @doc """
  Calls any Python function dynamically without requiring generated bindings.

  This is the no-codegen escape hatch for calling functions that were not
  scanned during compilation.
  """
  @spec call_dynamic(String.t(), function_name(), args(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def call_dynamic(module_path, function, args \\ [], opts \\ []) when is_binary(module_path) do
    {args, opts} = normalize_args_opts(args, opts)
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)

    # Determine session_id ONCE - this is the single source of truth
    session_id = resolve_session_id(runtime_opts)

    payload =
      protocol_payload()
      |> Map.put("call_type", "dynamic")
      |> Map.put("module_path", module_path)
      |> Map.put("function", to_string(function))
      |> Map.put("args", encoded_args)
      |> Map.put("kwargs", encoded_kwargs)
      |> Map.put("idempotent", idempotent)
      |> maybe_put_session_id(session_id)

    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    metadata = %{
      module: module_path,
      function: to_string(function),
      library: module_path |> String.split(".") |> List.first(),
      python_module: module_path,
      call_type: "dynamic"
    }

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @spec call_helper(String.t(), args(), opts() | map()) :: {:ok, term()} | {:error, term()}
  def call_helper(helper, args \\ [], opts \\ [])

  def call_helper(helper, args, opts) when is_map(opts) do
    encoded_args = encode_args(args)
    encoded_kwargs = encode_kwargs(stringify_keys(opts))
    # Map opts cannot have __runtime__, use context/auto-session
    session_id = resolve_session_id([])

    payload =
      helper_payload(helper, encoded_args, encoded_kwargs, false)
      |> Map.put("session_id", session_id)

    runtime_opts = ensure_session_opt([], session_id)
    metadata = helper_metadata(helper)

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> classify_helper_result(helper)
    |> decode_result()
  end

  def call_helper(helper, args, opts) when is_list(opts) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)
    # Determine session_id ONCE using correct priority
    session_id = resolve_session_id(runtime_opts)

    payload =
      helper_payload(helper, encoded_args, encoded_kwargs, idempotent)
      |> Map.put("session_id", session_id)

    runtime_opts = ensure_session_opt(runtime_opts, session_id)
    metadata = helper_metadata(helper)

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> classify_helper_result(helper)
    |> decode_result()
  end

  @doc """
  Stream results from a Python generator/iterator.

  ## Parameters

  - `module` - Either a generated SnakeBridge module atom OR a Python module path string
  - `function` - Function name (atom or string)
  - `args` - Positional arguments (list)
  - `opts` - Options including kwargs
  - `callback` - Function called for each streamed item

  ## Performance

  When called with a **generated module atom**, this function can use Snakepit's
  native gRPC streaming for efficient data transfer.

  When called with a **string module path**, this delegates to `stream_dynamic/5`
  which uses RPC-per-item iteration. See `stream_dynamic/5` docs for performance
  guidance on large streams.

  ## Examples

      # With string module path (dynamic, RPC-per-item)
      SnakeBridge.Runtime.stream("pandas", "read_csv", ["file.csv"], [chunksize: 100], fn chunk ->
        process(chunk)
      end)

      # With generated module (native streaming when available)
      SnakeBridge.Runtime.stream(MyApp.Pandas, :read_csv, ["file.csv"], [chunksize: 100], fn chunk ->
        process(chunk)
      end)

  """
  @spec stream(module_ref() | String.t(), function_name() | String.t(), args(), opts(), (term() ->
                                                                                           any())) ::
          :ok | {:ok, :done} | {:error, Snakepit.Error.t()}
  def stream(module, function, args \\ [], opts \\ [], callback)

  # String module path - use stream_dynamic
  def stream(module, function, args, opts, callback)
      when is_binary(module) and is_function(callback, 1) do
    function_name = to_string(function)
    stream_dynamic(module, function_name, args, opts, callback)
  end

  # Atom module - existing behavior
  def stream(module, function, args, opts, callback)
      when is_atom(module) and is_function(callback, 1) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)
    # Determine session_id ONCE using correct priority
    session_id = resolve_session_id(runtime_opts)

    payload =
      base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
      |> Map.put("session_id", session_id)

    runtime_opts = ensure_session_opt(runtime_opts, session_id)
    metadata = call_metadata(payload, module, function, "stream")
    decode_callback = fn chunk -> callback.(Types.decode(chunk)) end

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute_stream(
        "snakebridge.stream",
        payload,
        decode_callback,
        runtime_opts
      )
    end)
    |> apply_error_mode()
  end

  @doc """
  Stream results from a Python generator using dynamic dispatch.

  Creates a stream reference and iterates via stream_next until exhausted.

  ## Performance Note

  Dynamic streaming uses an RPC-per-item approach: each item from the Python
  iterator triggers a separate `stream_next` gRPC call. This is correct and
  safe but may be slow for large streams (thousands of items).

  For high-throughput streaming workloads, consider:
  - **Generated streaming wrappers**: Use `SnakeBridge.stream/5` with compiled
    modules, which can leverage Snakepit's server-side streaming for better
    throughput.
  - **Batched iteration**: Have Python yield batches of items rather than
    individual items.
  - **Dedicated data transfer**: For very large datasets, consider writing
    Python results to files/databases and loading from Elixir.

  Dynamic streaming is ideal for convenience and moderate-sized iterables.
  """
  @spec stream_dynamic(String.t(), String.t(), args(), opts(), (term() -> any())) ::
          {:ok, :done} | {:error, term()}
  def stream_dynamic(module_path, function, args, opts, callback)
      when is_binary(module_path) and is_function(callback, 1) do
    case call_dynamic(module_path, function, args, opts) do
      {:ok, %SnakeBridge.StreamRef{} = stream_ref} ->
        stream_iterate(stream_ref, callback, [])

      {:ok, %SnakeBridge.Ref{} = ref} ->
        # Try to iterate if it's an iterator
        stream_iterate_ref(ref, callback, [])

      {:ok, other} ->
        # Not a stream/iterator - return as single value
        callback.(other)
        {:ok, :done}

      error ->
        error
    end
  end

  defp stream_iterate(stream_ref, callback, opts) do
    case stream_next(stream_ref, opts) do
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
    case call_method(ref, :__iter__, [], opts) do
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
    case call_method(ref, :__next__, [], opts) do
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

  @doc """
  Gets the next item from a Python iterator or generator.

  Each call makes a separate RPC to Python. For high-throughput streaming,
  see the performance note on `stream_dynamic/5`.
  """
  @spec stream_next(SnakeBridge.StreamRef.t(), opts()) ::
          {:ok, term()} | {:error, :stop_iteration} | {:error, Snakepit.Error.t()}
  def stream_next(stream_ref, opts \\ []) do
    {_args, opts} = normalize_args_opts([], opts)
    {_, _, _, runtime_opts} = split_opts(opts)

    wire_ref = SnakeBridge.StreamRef.to_wire_format(stream_ref)
    # Single source of truth: prioritize runtime_opts, then stream_ref session, then context
    session_id = resolve_session_id(runtime_opts, stream_ref)
    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    payload =
      protocol_payload()
      |> Map.put("call_type", "stream_next")
      |> Map.put("stream_ref", wire_ref)
      |> maybe_put_session_id(session_id)

    result =
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
      |> apply_error_mode()

    case result do
      {:ok, %{"__type__" => "stop_iteration"}} ->
        {:error, :stop_iteration}

      {:ok, value} ->
        {:ok, Types.decode(value)}

      error ->
        error
    end
  end

  @doc """
  Gets the length of a Python iterable (if supported).
  """
  @spec stream_len(SnakeBridge.StreamRef.t(), opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def stream_len(stream_ref, opts \\ []) do
    wire_ref = SnakeBridge.StreamRef.to_wire_format(stream_ref)
    call_method(wire_ref, :__len__, [], opts)
  end

  @spec call_class(module_ref(), function_name(), args(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def call_class(module, function, args \\ [], opts \\ []) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)
    # Determine session_id ONCE using correct priority
    session_id = resolve_session_id(runtime_opts)

    payload =
      module
      |> base_payload(function, encoded_args, encoded_kwargs, idempotent)
      |> Map.put("call_type", "class")
      |> Map.put("class", python_class_name(module))
      |> Map.put("session_id", session_id)

    runtime_opts = ensure_session_opt(runtime_opts, session_id)
    metadata = call_metadata(payload, module, function, "class")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @spec call_method(SnakeBridge.Ref.t() | map(), function_name(), args(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def call_method(ref, function, args \\ [], opts \\ []) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)
    wire_ref = normalize_ref(ref)
    # Single source of truth: prioritize runtime_opts, then ref session, then context
    session_id = resolve_session_id(runtime_opts, wire_ref)
    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    payload =
      wire_ref
      |> base_payload_for_ref(function, encoded_args, encoded_kwargs, idempotent)
      |> Map.put("call_type", "method")
      |> Map.put("instance", wire_ref)
      |> Map.put("session_id", session_id)

    metadata = ref_metadata(payload, function, "method")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @doc """
  Retrieves a module-level attribute (constant, class, etc.).

  ## Parameters

  - `module` - Either a generated SnakeBridge module atom OR a Python module path string
  - `attr` - Attribute name (atom or string)
  - `opts` - Runtime options

  ## Examples

      # Get math.pi
      {:ok, pi} = SnakeBridge.Runtime.get_module_attr("math", "pi")
      {:ok, pi} = SnakeBridge.Runtime.get_module_attr("math", :pi)

  """
  @spec get_module_attr(module_ref() | String.t(), atom() | String.t(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def get_module_attr(module, attr, opts \\ [])

  # String module path
  def get_module_attr(module, attr, opts) when is_binary(module) do
    {_kwargs, _idempotent, _extra_args, runtime_opts} = split_opts(opts)
    attr_name = to_string(attr)
    # Determine session_id ONCE using correct priority
    session_id = resolve_session_id(runtime_opts)
    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    payload =
      protocol_payload()
      |> Map.put("call_type", "module_attr")
      |> Map.put("python_module", module)
      |> Map.put("library", library_from_module_path(module))
      |> Map.put("attr", attr_name)
      |> Map.put("session_id", session_id)

    metadata = %{
      module: module,
      function: attr_name,
      library: library_from_module_path(module),
      python_module: module,
      call_type: "module_attr"
    }

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  # Atom module - existing behavior
  def get_module_attr(module, attr, opts) when is_atom(module) do
    {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)
    encoded_kwargs = encode_kwargs(kwargs)
    # Determine session_id ONCE using correct priority
    session_id = resolve_session_id(runtime_opts)

    payload =
      module
      |> base_payload(attr, [], encoded_kwargs, idempotent)
      |> Map.put("call_type", "module_attr")
      |> Map.put("attr", to_string(attr))
      |> Map.put("session_id", session_id)

    runtime_opts = ensure_session_opt(runtime_opts, session_id)
    metadata = call_metadata(payload, module, attr, "module_attr")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  # Helper to extract library name from module path
  defp library_from_module_path(module_path) when is_binary(module_path) do
    module_path
    |> String.split(".")
    |> List.first()
  end

  @spec get_attr(SnakeBridge.Ref.t(), atom() | String.t(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def get_attr(ref, attr, opts \\ []) do
    {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)
    encoded_kwargs = encode_kwargs(kwargs)
    wire_ref = normalize_ref(ref)
    # Single source of truth: prioritize runtime_opts, then ref session, then context
    session_id = resolve_session_id(runtime_opts, wire_ref)
    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    payload =
      wire_ref
      |> base_payload_for_ref(attr, [], encoded_kwargs, idempotent)
      |> Map.put("call_type", "get_attr")
      |> Map.put("instance", wire_ref)
      |> Map.put("attr", to_string(attr))

    metadata = ref_metadata(payload, attr, "get_attr")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @doc false
  def build_module_attr_payload(module, attr) do
    module
    |> base_payload(attr, [], %{}, false)
    |> Map.put("call_type", "module_attr")
    |> Map.put("attr", to_string(attr))
  end

  @doc false
  def build_dynamic_payload(module_path, function, args, opts) do
    {args, opts} = normalize_args_opts(args, opts)
    {kwargs, idempotent, extra_args, _runtime_opts} = split_opts(opts)

    protocol_payload()
    |> Map.put("call_type", "dynamic")
    |> Map.put("module_path", module_path)
    |> Map.put("function", to_string(function))
    |> Map.put("args", List.wrap(args ++ extra_args))
    |> Map.put("kwargs", Map.new(kwargs, fn {key, value} -> {to_string(key), value} end))
    |> Map.put("idempotent", idempotent)
    |> maybe_put_session_id(current_session_id())
  end

  @spec set_attr(SnakeBridge.Ref.t(), atom() | String.t(), term(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def set_attr(ref, attr, value, opts \\ []) do
    {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)
    encoded_kwargs = encode_kwargs(kwargs)
    encoded_args = encode_args([value])
    wire_ref = normalize_ref(ref)
    # Single source of truth: prioritize runtime_opts, then ref session, then context
    session_id = resolve_session_id(runtime_opts, wire_ref)
    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    payload =
      wire_ref
      |> base_payload_for_ref(attr, encoded_args, encoded_kwargs, idempotent)
      |> Map.put("call_type", "set_attr")
      |> Map.put("instance", wire_ref)
      |> Map.put("attr", to_string(attr))

    metadata = ref_metadata(payload, attr, "set_attr")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @spec release_ref(SnakeBridge.Ref.t(), opts()) :: :ok | {:error, Snakepit.Error.t()}
  def release_ref(ref, opts \\ []) do
    {_, _, _, runtime_opts} = split_opts(opts)
    wire_ref = normalize_ref(ref)
    # Single source of truth: prioritize runtime_opts, then ref session, then context
    session_id = resolve_session_id(runtime_opts, wire_ref)
    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    payload =
      protocol_payload()
      |> Map.put("ref", wire_ref)
      |> maybe_put_session_id(session_id)

    runtime_client().execute("snakebridge.release_ref", payload, runtime_opts)
    |> apply_error_mode()
    |> normalize_release_result()
  end

  @spec release_session(String.t(), opts()) :: :ok | {:error, Snakepit.Error.t()}
  def release_session(session_id, opts \\ []) when is_binary(session_id) do
    {_, _, _, runtime_opts} = split_opts(opts)
    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    payload =
      protocol_payload()
      |> Map.put("session_id", session_id)

    runtime_client().execute("snakebridge.release_session", payload, runtime_opts)
    |> apply_error_mode()
    |> normalize_release_result()
  end

  defp runtime_client do
    Application.get_env(:snakebridge, :runtime_client, Snakepit)
  end

  defp execute_with_telemetry(metadata, fun) do
    start_time = System.monotonic_time()

    emit_runtime_event(
      [:snakepit, :python, :call, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      case result do
        {:error, reason} ->
          emit_runtime_event(
            [:snakepit, :python, :call, :exception],
            %{duration: System.monotonic_time() - start_time},
            Map.put(metadata, :error, reason)
          )

        _ ->
          emit_runtime_event(
            [:snakepit, :python, :call, :stop],
            %{duration: System.monotonic_time() - start_time},
            metadata
          )
      end

      result
    rescue
      exception ->
        emit_runtime_event(
          [:snakepit, :python, :call, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.put(metadata, :reason, exception)
        )

        reraise exception, __STACKTRACE__
    end
  end

  defp emit_runtime_event(event, measurements, metadata) do
    case Application.ensure_all_started(:telemetry) do
      {:ok, _} -> :telemetry.execute(event, measurements, metadata)
      {:error, _} -> :ok
    end
  end

  defp call_metadata(payload, module, function, call_type) do
    %{
      module: module,
      function: to_string(function),
      library: payload["library"],
      python_module: payload["python_module"],
      call_type: call_type
    }
  end

  defp ref_metadata(payload, function, call_type) do
    %{
      module: payload["python_module"],
      function: to_string(function),
      library: payload["library"],
      python_module: payload["python_module"],
      call_type: call_type
    }
  end

  defp helper_metadata(helper) do
    %{
      module: helper,
      function: helper,
      library: helper_library(helper),
      python_module: helper_library(helper),
      call_type: "helper"
    }
  end

  defp split_opts(opts) do
    extra_args = Keyword.get(opts, :__args__, [])
    idempotent = Keyword.get(opts, :idempotent, false)
    runtime_opts = Keyword.get(opts, :__runtime__, [])

    kwargs =
      opts
      |> Keyword.drop([:__args__, :idempotent, :__runtime__])
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)

    {kwargs, idempotent, List.wrap(extra_args), runtime_opts}
  end

  # Session ID single source of truth: determine once, use everywhere
  # Priority: runtime_opts override > ref session_id > context session > auto-session
  @doc false
  def resolve_session_id(runtime_opts, ref \\ nil) do
    session_id_from_runtime_opts(runtime_opts) ||
      session_id_from_ref(ref) ||
      current_session_id()
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

  defp ensure_session_opt(runtime_opts, session_id) when is_binary(session_id) do
    cond do
      runtime_opts == nil ->
        [session_id: session_id]

      is_list(runtime_opts) ->
        Keyword.put_new(runtime_opts, :session_id, session_id)

      true ->
        runtime_opts
    end
  end

  defp ensure_session_opt(runtime_opts, _session_id), do: runtime_opts

  @doc false
  @spec normalize_args_opts(list(), keyword()) :: {list(), keyword()}
  def normalize_args_opts(args, opts) do
    if opts == [] and Keyword.keyword?(args) do
      {[], args}
    else
      {args, opts}
    end
  end

  defp base_payload(module, function, args, kwargs, idempotent) do
    python_module = python_module_name(module)

    %{
      "protocol_version" => @protocol_version,
      "min_supported_version" => @min_supported_version,
      "library" => library_name(module, python_module),
      "python_module" => python_module,
      "function" => to_string(function),
      "args" => List.wrap(args),
      "kwargs" => kwargs,
      "idempotent" => idempotent
    }
    |> maybe_put_session_id(current_session_id())
  end

  defp base_payload_for_ref(ref, function, args, kwargs, idempotent) do
    python_module =
      ref_field(ref, "python_module") || ref_field(ref, "library") || python_module_name(ref)

    library = ref_field(ref, "library") || library_name(ref, python_module)
    session_id = ref_field(ref, "session_id") || current_session_id()

    %{
      "protocol_version" => @protocol_version,
      "min_supported_version" => @min_supported_version,
      "library" => library,
      "python_module" => python_module,
      "function" => to_string(function),
      "args" => List.wrap(args),
      "kwargs" => kwargs,
      "idempotent" => idempotent
    }
    |> maybe_put_session_id(session_id)
  end

  defp python_module_name(module) when is_atom(module) do
    if function_exported?(module, :__snakebridge_python_name__, 0) do
      module.__snakebridge_python_name__()
    else
      module
      |> Module.split()
      |> Enum.map_join(".", &Macro.underscore/1)
    end
  end

  defp python_module_name(%{python_module: python_module}) when is_binary(python_module),
    do: python_module

  defp python_module_name(_), do: "unknown"

  defp library_name(module, python_module) when is_atom(module) do
    if function_exported?(module, :__snakebridge_library__, 0) do
      module.__snakebridge_library__()
    else
      python_module |> String.split(".") |> List.first()
    end
  end

  defp library_name(_module, python_module) do
    python_module |> String.split(".") |> List.first()
  end

  defp python_class_name(module) when is_atom(module) do
    if function_exported?(module, :__snakebridge_python_class__, 0) do
      module.__snakebridge_python_class__()
    else
      module |> Module.split() |> List.last()
    end
  end

  defp helper_payload(helper, args, kwargs, idempotent) do
    %{
      "protocol_version" => @protocol_version,
      "min_supported_version" => @min_supported_version,
      "call_type" => "helper",
      "helper" => helper,
      "function" => helper,
      "library" => helper_library(helper),
      "args" => List.wrap(args),
      "kwargs" => kwargs,
      "idempotent" => idempotent,
      "helper_config" => SnakeBridge.Helpers.payload_config(SnakeBridge.Helpers.runtime_config())
    }
    |> maybe_put_session_id(current_session_id())
  end

  @doc false
  def protocol_payload do
    %{
      "protocol_version" => @protocol_version,
      "min_supported_version" => @min_supported_version
    }
  end

  defp helper_library(helper) when is_binary(helper) do
    case String.split(helper, ".", parts: 2) do
      [library, _rest] -> library
      _ -> "unknown"
    end
  end

  defp helper_library(_), do: "unknown"

  defp current_session_id do
    case SnakeBridge.SessionContext.current() do
      %{session_id: session_id} when is_binary(session_id) -> session_id
      _ -> ensure_auto_session()
    end
  end

  # Auto-session management

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
        # Release on Python side
        release_session(session_id)
        # Unregister from SessionManager
        SessionManager.unregister_session(session_id)
        # Clear from process dictionary
        Process.delete(@auto_session_key)
        :ok
    end
  end

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
    # Store in process dictionary
    Process.put(@auto_session_key, session_id)

    # Register with SessionManager for monitoring
    # This ensures cleanup when the process dies
    SessionManager.register_session(session_id, self())

    # Ensure Snakepit session exists (if SessionStore is available)
    ensure_snakepit_session(session_id)
  end

  defp ensure_snakepit_session(session_id) do
    # Only call if SessionStore module is available
    # Use apply/3 to avoid compile-time warnings about undefined module
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

  defp maybe_put_session_id(payload, nil), do: payload

  defp maybe_put_session_id(payload, session_id) when is_binary(session_id) do
    Map.put(payload, "session_id", session_id)
  end

  defp classify_helper_result({:error, reason}, helper) do
    {:error, classify_helper_error(reason, helper)}
  end

  defp classify_helper_result(result, _helper), do: result

  defp classify_helper_error({:invalid_parameter, :json_encode_failed, message}, _helper) do
    SnakeBridge.SerializationError.new(message)
  end

  defp classify_helper_error(
         %{python_type: "SnakeBridgeHelperNotFoundError", message: message},
         helper
       ) do
    helper_name = extract_helper_name(message) || helper
    SnakeBridge.HelperNotFoundError.new(helper_name)
  end

  defp classify_helper_error(
         %{python_type: "SnakeBridgeSerializationError", message: message},
         _helper
       ) do
    SnakeBridge.SerializationError.new(message)
  end

  defp classify_helper_error(reason, _helper), do: reason

  defp extract_helper_name(message) when is_binary(message) do
    case Regex.run(~r/Helper ['"]([^'"]+)['"]/, message) do
      [_, helper] -> helper
      _ -> nil
    end
  end

  defp extract_helper_name(_), do: nil

  defp encode_args(args) do
    args
    |> List.wrap()
    |> Enum.map(&Types.encode/1)
  end

  defp encode_kwargs(kwargs) do
    kwargs
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), Types.encode(value)} end)
  end

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp decode_result({:ok, value}), do: {:ok, Types.decode(value)}
  defp decode_result(result), do: result

  defp apply_error_mode({:error, reason}) do
    case error_mode() do
      :raw ->
        {:error, reason}

      :translated ->
        {:error, translate_reason(reason)}

      :raise_translated ->
        translated = translate_reason(reason)

        if translated == reason do
          {:error, reason}
        else
          raise translated
        end
    end
  end

  defp apply_error_mode(result), do: result

  defp normalize_release_result({:ok, _}), do: :ok
  defp normalize_release_result(:ok), do: :ok
  defp normalize_release_result(result), do: result

  defp translate_reason(reason) do
    case python_error_payload(reason) do
      {_message, traceback, type} when is_binary(type) ->
        translated = SnakeBridge.ErrorTranslator.translate(reason, traceback)
        if translated == reason, do: reason, else: translated

      {message, traceback, _type} when is_binary(message) ->
        translated =
          SnakeBridge.ErrorTranslator.translate(%RuntimeError{message: message}, traceback)

        case translated do
          %RuntimeError{} -> reason
          _ -> translated
        end

      _ ->
        reason
    end
  end

  defp python_error_payload(error) when is_map(error) do
    {extract_error_message(error), extract_error_traceback(error), extract_error_type(error)}
  end

  defp python_error_payload(_), do: {nil, nil, nil}

  defp extract_error_message(error) do
    get_first_present(error, [:message, "message", :error, "error"])
  end

  defp extract_error_traceback(error) do
    get_first_present(error, [:traceback, "traceback", :python_traceback, "python_traceback"])
  end

  defp extract_error_type(error) do
    get_first_present(error, [:python_type, "python_type", :error_type, "error_type"])
  end

  defp get_first_present(map, keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp error_mode do
    Application.get_env(:snakebridge, :error_mode, :raw)
  end

  defp ref_field(ref, "python_module") when is_map(ref),
    do: Map.get(ref, "python_module") || Map.get(ref, :python_module)

  defp ref_field(ref, "library") when is_map(ref),
    do: Map.get(ref, "library") || Map.get(ref, :library)

  defp ref_field(ref, "session_id") when is_map(ref),
    do: Map.get(ref, "session_id") || Map.get(ref, :session_id)

  defp ref_field(ref, "id") when is_map(ref),
    do: Map.get(ref, "id") || Map.get(ref, :id) || Map.get(ref, "ref_id") || Map.get(ref, :ref_id)

  defp ref_field(_ref, _key), do: nil

  defp normalize_ref(%SnakeBridge.Ref{} = ref), do: SnakeBridge.Ref.to_wire_format(ref)

  defp normalize_ref(ref) when is_map(ref) do
    if Map.get(ref, "__type__") == "ref" or Map.get(ref, :__type__) == "ref" do
      SnakeBridge.Ref.to_wire_format(ref)
    else
      ref
    end
  end

  defp normalize_ref(ref), do: ref
end
