defmodule SnakeBridge.Runtime do
  @moduledoc """
  Thin payload helper for SnakeBridge that delegates execution to Snakepit.

  This module is compile-time agnostic and focuses on building payloads that
  match the Snakepit Prime runtime contract.
  """

  alias SnakeBridge.Runtime.{Payload, SessionResolver, Streamer}
  alias SnakeBridge.Types

  @type module_ref :: module()
  @type function_name :: atom() | String.t()
  @type args :: list()
  @type opts :: keyword()
  @type error_reason :: Snakepit.Error.t() | Exception.t()

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
          {:ok, term()} | {:error, error_reason()}
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
      Payload.base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
      |> Map.put("session_id", session_id)

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

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
          {:ok, term()} | {:error, error_reason()}
  def call_dynamic(module_path, function, args \\ [], opts \\ []) when is_binary(module_path) do
    {args, opts} = normalize_args_opts(args, opts)
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)

    # Determine session_id ONCE - this is the single source of truth
    session_id = resolve_session_id(runtime_opts)

    library = Payload.library_from_module_path(module_path)

    payload =
      protocol_payload()
      |> Map.put("call_type", "dynamic")
      |> Map.put("module_path", module_path)
      |> Map.put("library", library)
      |> Map.put("function", to_string(function))
      |> Map.put("args", encoded_args)
      |> Map.put("kwargs", encoded_kwargs)
      |> Map.put("idempotent", idempotent)
      |> Payload.maybe_put_session_id(session_id)

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

    metadata = %{
      module: module_path,
      function: to_string(function),
      library: library,
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
      Payload.helper_payload(helper, encoded_args, encoded_kwargs, false, session_id)
      |> Map.put("session_id", session_id)

    runtime_opts =
      []
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

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
      Payload.helper_payload(helper, encoded_args, encoded_kwargs, idempotent, session_id)
      |> Map.put("session_id", session_id)

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

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
          :ok | {:ok, :done} | {:error, error_reason()}
  defdelegate stream(module, function, args \\ [], opts \\ [], callback), to: Streamer

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
  defdelegate stream_dynamic(module_path, function, args, opts, callback), to: Streamer

  @doc """
  Gets the next item from a Python iterator or generator.

  Each call makes a separate RPC to Python. For high-throughput streaming,
  see the performance note on `stream_dynamic/5`.
  """
  @spec stream_next(SnakeBridge.StreamRef.t(), opts()) ::
          {:ok, term()} | {:error, :stop_iteration} | {:error, error_reason()}
  def stream_next(stream_ref, opts \\ []) do
    {_args, opts} = normalize_args_opts([], opts)
    {_, _, _, runtime_opts} = split_opts(opts)

    wire_ref = SnakeBridge.StreamRef.to_wire_format(stream_ref)
    # Single source of truth: prioritize runtime_opts, then stream_ref session, then context
    session_id = resolve_session_id(runtime_opts, stream_ref)

    library =
      case stream_ref.library do
        lib when is_binary(lib) and lib != "" -> lib
        _ -> "unknown"
      end

    payload =
      protocol_payload()
      |> Map.put("call_type", "stream_next")
      |> Map.put("stream_ref", wire_ref)
      |> Map.put("library", library)
      |> Payload.maybe_put_session_id(session_id)

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :stream)
      |> ensure_session_opt(session_id)

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
          {:ok, term()} | {:error, error_reason()}
  def call_class(module, function, args \\ [], opts \\ []) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)
    # Determine session_id ONCE using correct priority
    session_id = resolve_session_id(runtime_opts)

    payload =
      module
      |> Payload.base_payload(function, encoded_args, encoded_kwargs, idempotent)
      |> Map.put("call_type", "class")
      |> Map.put("class", Payload.python_class_name(module))
      |> Map.put("session_id", session_id)

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

    metadata = call_metadata(payload, module, function, "class")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @spec call_method(SnakeBridge.Ref.t() | map(), function_name(), args(), opts()) ::
          {:ok, term()} | {:error, error_reason()}
  def call_method(ref, function, args \\ [], opts \\ []) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    encoded_args = encode_args(args ++ extra_args)
    encoded_kwargs = encode_kwargs(kwargs)
    wire_ref = normalize_ref(ref)
    # Single source of truth: prioritize runtime_opts, then ref session, then context
    session_id = resolve_session_id(runtime_opts, wire_ref)

    payload =
      wire_ref
      |> Payload.base_payload_for_ref(
        function,
        encoded_args,
        encoded_kwargs,
        idempotent,
        session_id
      )
      |> Map.put("call_type", "method")
      |> Map.put("instance", wire_ref)
      |> Map.put("session_id", session_id)

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

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
          {:ok, term()} | {:error, error_reason()}
  def get_module_attr(module, attr, opts \\ [])

  # String module path
  def get_module_attr(module, attr, opts) when is_binary(module) do
    {_kwargs, _idempotent, _extra_args, runtime_opts} = split_opts(opts)
    attr_name = to_string(attr)
    # Determine session_id ONCE using correct priority
    session_id = resolve_session_id(runtime_opts)

    payload =
      protocol_payload()
      |> Map.put("call_type", "module_attr")
      |> Map.put("python_module", module)
      |> Map.put("library", Payload.library_from_module_path(module))
      |> Map.put("attr", attr_name)
      |> Map.put("session_id", session_id)

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

    metadata = %{
      module: module,
      function: attr_name,
      library: Payload.library_from_module_path(module),
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
      |> Payload.base_payload(attr, [], encoded_kwargs, idempotent)
      |> Map.put("call_type", "module_attr")
      |> Map.put("attr", to_string(attr))
      |> Map.put("session_id", session_id)

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

    metadata = call_metadata(payload, module, attr, "module_attr")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @spec get_attr(SnakeBridge.Ref.t(), atom() | String.t(), opts()) ::
          {:ok, term()} | {:error, error_reason()}
  def get_attr(ref, attr, opts \\ []) do
    {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)
    encoded_kwargs = encode_kwargs(kwargs)
    wire_ref = normalize_ref(ref)
    # Single source of truth: prioritize runtime_opts, then ref session, then context
    session_id = resolve_session_id(runtime_opts, wire_ref)

    payload =
      wire_ref
      |> Payload.base_payload_for_ref(attr, [], encoded_kwargs, idempotent, session_id)
      |> Map.put("call_type", "get_attr")
      |> Map.put("instance", wire_ref)
      |> Map.put("attr", to_string(attr))

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

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
    |> Payload.base_payload(attr, [], %{}, false, SessionResolver.current_session_id())
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
    |> Payload.maybe_put_session_id(SessionResolver.current_session_id())
  end

  @spec set_attr(SnakeBridge.Ref.t(), atom() | String.t(), term(), opts()) ::
          {:ok, term()} | {:error, error_reason()}
  def set_attr(ref, attr, value, opts \\ []) do
    {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)
    encoded_kwargs = encode_kwargs(kwargs)
    encoded_args = encode_args([value])
    wire_ref = normalize_ref(ref)
    # Single source of truth: prioritize runtime_opts, then ref session, then context
    session_id = resolve_session_id(runtime_opts, wire_ref)

    payload =
      wire_ref
      |> Payload.base_payload_for_ref(attr, encoded_args, encoded_kwargs, idempotent, session_id)
      |> Map.put("call_type", "set_attr")
      |> Map.put("instance", wire_ref)
      |> Map.put("attr", to_string(attr))

    runtime_opts =
      runtime_opts
      |> apply_runtime_defaults(payload, :call)
      |> ensure_session_opt(session_id)

    metadata = ref_metadata(payload, attr, "set_attr")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> apply_error_mode()
    |> decode_result()
  end

  @spec release_ref(SnakeBridge.Ref.t(), opts()) :: :ok | {:error, error_reason()}
  def release_ref(ref, opts \\ []) do
    {_, _, _, runtime_opts} = split_opts(opts)
    wire_ref = normalize_ref(ref)
    # Single source of truth: prioritize runtime_opts, then ref session, then context
    session_id = resolve_session_id(runtime_opts, wire_ref)
    runtime_opts = ensure_session_opt(runtime_opts, session_id)

    payload =
      protocol_payload()
      |> Map.put("ref", wire_ref)
      |> Payload.maybe_put_session_id(session_id)

    runtime_client().execute("snakebridge.release_ref", payload, runtime_opts)
    |> apply_error_mode()
    |> normalize_release_result()
  end

  @spec release_session(String.t(), opts()) :: :ok | {:error, error_reason()}
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

  @doc false
  def runtime_client do
    Application.get_env(:snakebridge, :runtime_client, Snakepit)
  end

  @doc false
  def execute_with_telemetry(metadata, fun) do
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

  @doc false
  def call_metadata(payload, module, function, call_type) do
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
      library: Payload.helper_library(helper),
      python_module: Payload.helper_library(helper),
      call_type: "helper"
    }
  end

  @doc false
  def split_opts(opts) do
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
    SessionResolver.resolve_session_id(runtime_opts, ref)
  end

  defp ensure_session_opt(runtime_opts, session_id) do
    SessionResolver.ensure_session_opt(runtime_opts, session_id)
  end

  # ============================================================================
  # Runtime Timeout Defaults
  # ============================================================================

  # Applies runtime timeout defaults to the given runtime options.
  #
  # This function merges profile-based timeouts with user-provided options,
  # respecting the following priority (highest to lowest):
  # 1. Explicit user-provided options (e.g., `timeout: 60_000`)
  # 2. User-selected profile (via `timeout_profile:` or `profile:`)
  # 3. Library-specific profile (from `runtime.library_profiles` config)
  # 4. Default profile based on call kind (`:default` for calls, `:streaming` for streams)
  @doc false
  @spec apply_runtime_defaults(keyword() | nil, map(), atom()) :: keyword()
  def apply_runtime_defaults(runtime_opts, payload, call_kind) do
    runtime_opts = List.wrap(runtime_opts || [])
    library = payload["library"]

    profile = resolve_timeout_profile(runtime_opts, library, call_kind)
    profile_opts = get_profile_opts(profile)

    # Merge: profile defaults < user overrides
    merged =
      profile_opts
      |> Keyword.merge(runtime_opts)

    merged
    |> Keyword.put_new(:timeout_profile, profile)
    |> Keyword.put_new(:timeout, SnakeBridge.Defaults.runtime_default_timeout())
    |> maybe_put_stream_defaults(call_kind)
  end

  defp resolve_timeout_profile(runtime_opts, library, call_kind) do
    # Priority: explicit > library_profiles > global default
    Keyword.get(runtime_opts, :timeout_profile) ||
      Keyword.get(runtime_opts, :profile) ||
      library_profile(library) ||
      SnakeBridge.Defaults.runtime_timeout_profile(call_kind)
  end

  defp get_profile_opts(profile) do
    SnakeBridge.Defaults.runtime_profiles()
    |> Map.get(profile, [])
  end

  defp library_profile(nil), do: nil

  defp library_profile(library) when is_binary(library) do
    profiles = SnakeBridge.Defaults.runtime_library_profiles()

    Map.get(profiles, library) ||
      Map.get(profiles, String.to_existing_atom(library))
  rescue
    ArgumentError -> nil
  end

  defp library_profile(_), do: nil

  defp maybe_put_stream_defaults(opts, :stream) do
    Keyword.put_new(opts, :stream_timeout, SnakeBridge.Defaults.runtime_default_stream_timeout())
  end

  defp maybe_put_stream_defaults(opts, _), do: opts

  @doc false
  @spec normalize_args_opts(list(), keyword()) :: {list(), keyword()}
  def normalize_args_opts(args, opts) do
    if opts == [] and Keyword.keyword?(args) do
      {[], args}
    else
      {args, opts}
    end
  end

  @doc false
  defdelegate protocol_payload(), to: Payload

  @doc """
  Returns the current session ID (explicit or auto-generated).

  This is useful for debugging or when you need to know which session is active.
  """
  @spec current_session() :: String.t()
  defdelegate current_session(), to: SessionResolver

  @doc """
  Clears the auto-session for the current process.

  Useful for testing or when you want to force a new session.
  Does NOT release the session on the Python side - use `release_auto_session/0` for that.
  """
  @spec clear_auto_session() :: :ok
  defdelegate clear_auto_session(), to: SessionResolver

  @doc """
  Releases and clears the auto-session for the current process.

  This releases all refs associated with the session on both Elixir and Python sides.
  """
  @spec release_auto_session() :: :ok
  defdelegate release_auto_session(), to: SessionResolver

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

  @doc false
  def encode_args(args) do
    args
    |> List.wrap()
    |> Enum.map(&Types.encode/1)
  end

  @doc false
  def encode_kwargs(kwargs) do
    kwargs
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), Types.encode(value)} end)
  end

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp decode_result({:ok, value}), do: {:ok, Types.decode(value)}
  defp decode_result(result), do: result

  @doc false
  def apply_error_mode({:error, reason}) do
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

  def apply_error_mode(result), do: result

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
