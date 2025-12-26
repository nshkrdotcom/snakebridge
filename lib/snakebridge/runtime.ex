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
    runtime_client().execute("snakebridge.call", payload, runtime_opts)
  end

  @spec stream(module_ref(), function_name(), args(), opts(), (term() -> any())) ::
          :ok | {:error, Snakepit.Error.t()}
  def stream(module, function, args \\ [], opts \\ [], callback)
      when is_function(callback, 1) do
    {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
    payload = base_payload(module, function, args ++ extra_args, kwargs, idempotent)
    runtime_client().execute_stream("snakebridge.stream", payload, callback, runtime_opts)
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

    runtime_client().execute("snakebridge.call", payload, runtime_opts)
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

    runtime_client().execute("snakebridge.call", payload, runtime_opts)
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

    runtime_client().execute("snakebridge.call", payload, runtime_opts)
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

    runtime_client().execute("snakebridge.call", payload, runtime_opts)
  end

  defp runtime_client do
    Application.get_env(:snakebridge, :runtime_client, Snakepit)
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
end
