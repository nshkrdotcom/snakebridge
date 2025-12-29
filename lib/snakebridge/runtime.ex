defmodule SnakeBridge.Runtime do
  @moduledoc """
  Thin payload helper for SnakeBridge that delegates execution to Snakepit.

  This module is compile-time agnostic and focuses on building payloads that
  match the Snakepit Prime runtime contract.
  """

  @type module_ref :: module()
  @type function_name :: atom() | String.t()
  @type args :: list()
  @type opts :: keyword()

  @spec call(module_ref(), function_name(), args(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def call(module, function, args \\ [], opts \\ []) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    payload = base_payload(module, function, args ++ extra_args, kwargs, idempotent)
    metadata = call_metadata(payload, module, function, "function")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
  end

  @spec call_helper(String.t(), args(), opts() | map()) :: {:ok, term()} | {:error, term()}
  def call_helper(helper, args \\ [], opts \\ [])

  def call_helper(helper, args, opts) when is_map(opts) do
    payload = helper_payload(helper, args, stringify_keys(opts), false)
    metadata = helper_metadata(helper)

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, [])
    end)
    |> classify_helper_result(helper)
  end

  def call_helper(helper, args, opts) when is_list(opts) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    payload = helper_payload(helper, args ++ extra_args, kwargs, idempotent)
    metadata = helper_metadata(helper)

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
    |> classify_helper_result(helper)
  end

  @spec stream(module_ref(), function_name(), args(), opts(), (term() -> any())) ::
          :ok | {:error, Snakepit.Error.t()}
  def stream(module, function, args \\ [], opts \\ [], callback)
      when is_function(callback, 1) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    payload = base_payload(module, function, args ++ extra_args, kwargs, idempotent)
    metadata = call_metadata(payload, module, function, "stream")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute_stream("snakebridge.stream", payload, callback, runtime_opts)
    end)
  end

  @spec call_class(module_ref(), function_name(), args(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def call_class(module, function, args \\ [], opts \\ []) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)

    payload =
      module
      |> base_payload(function, args ++ extra_args, kwargs, idempotent)
      |> Map.put("call_type", "class")
      |> Map.put("class", python_class_name(module))

    metadata = call_metadata(payload, module, function, "class")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
  end

  @spec call_method(Snakepit.PyRef.t(), function_name(), args(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def call_method(ref, function, args \\ [], opts \\ []) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)

    payload =
      ref
      |> base_payload_for_ref(function, args ++ extra_args, kwargs, idempotent)
      |> Map.put("call_type", "method")
      |> Map.put("instance", ref)

    metadata = ref_metadata(payload, function, "method")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
  end

  @spec get_attr(Snakepit.PyRef.t(), atom() | String.t(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def get_attr(ref, attr, opts \\ []) do
    {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)

    payload =
      ref
      |> base_payload_for_ref(attr, [], kwargs, idempotent)
      |> Map.put("call_type", "get_attr")
      |> Map.put("instance", ref)
      |> Map.put("attr", to_string(attr))

    metadata = ref_metadata(payload, attr, "get_attr")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
  end

  @spec set_attr(Snakepit.PyRef.t(), atom() | String.t(), term(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def set_attr(ref, attr, value, opts \\ []) do
    {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)

    payload =
      ref
      |> base_payload_for_ref(attr, [value], kwargs, idempotent)
      |> Map.put("call_type", "set_attr")
      |> Map.put("instance", ref)
      |> Map.put("attr", to_string(attr))

    metadata = ref_metadata(payload, attr, "set_attr")

    execute_with_telemetry(metadata, fn ->
      runtime_client().execute("snakebridge.call", payload, runtime_opts)
    end)
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

  defp base_payload(module, function, args, kwargs, idempotent) do
    python_module = python_module_name(module)

    %{
      "library" => library_name(module, python_module),
      "python_module" => python_module,
      "function" => to_string(function),
      "args" => List.wrap(args),
      "kwargs" => kwargs,
      "idempotent" => idempotent
    }
  end

  defp base_payload_for_ref(ref, function, args, kwargs, idempotent) do
    python_module =
      Map.get(ref, :python_module) || Map.get(ref, :library) || python_module_name(ref)

    library = Map.get(ref, :library) || library_name(ref, python_module)

    %{
      "library" => library,
      "python_module" => python_module,
      "function" => to_string(function),
      "args" => List.wrap(args),
      "kwargs" => kwargs,
      "idempotent" => idempotent
    }
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
      "call_type" => "helper",
      "helper" => helper,
      "function" => helper,
      "library" => helper_library(helper),
      "args" => List.wrap(args),
      "kwargs" => kwargs,
      "idempotent" => idempotent,
      "helper_config" => SnakeBridge.Helpers.payload_config(SnakeBridge.Helpers.runtime_config())
    }
  end

  defp helper_library(helper) when is_binary(helper) do
    case String.split(helper, ".", parts: 2) do
      [library, _rest] -> library
      _ -> "unknown"
    end
  end

  defp helper_library(_), do: "unknown"

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

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end
end
