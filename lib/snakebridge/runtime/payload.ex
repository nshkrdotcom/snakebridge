defmodule SnakeBridge.Runtime.Payload do
  @moduledoc false

  @protocol_version 1
  @min_supported_version 1

  @doc false
  def protocol_payload do
    %{
      "protocol_version" => @protocol_version,
      "min_supported_version" => @min_supported_version
    }
  end

  @doc false
  def base_payload(module, function, args, kwargs, idempotent, session_id \\ nil) do
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
    |> maybe_put_session_id(session_id)
  end

  @doc false
  def base_payload_for_ref(ref, function, args, kwargs, idempotent, session_id \\ nil) do
    python_module =
      ref_field(ref, "python_module") || ref_field(ref, "library") || python_module_name(ref)

    library = ref_field(ref, "library") || library_name(ref, python_module)
    session_id = session_id || ref_field(ref, "session_id")

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

  @doc false
  def helper_payload(helper, args, kwargs, idempotent, session_id \\ nil) do
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
    |> maybe_put_session_id(session_id)
  end

  @doc false
  def library_from_module_path(module_path) when is_binary(module_path) do
    module_path
    |> String.split(".")
    |> List.first()
  end

  @doc false
  def python_class_name(module) when is_atom(module) do
    if function_exported?(module, :__snakebridge_python_class__, 0) do
      module.__snakebridge_python_class__()
    else
      module |> Module.split() |> List.last()
    end
  end

  @doc false
  def python_module_name(module) when is_atom(module) do
    if function_exported?(module, :__snakebridge_python_name__, 0) do
      module.__snakebridge_python_name__()
    else
      module
      |> Module.split()
      |> Enum.map_join(".", &Macro.underscore/1)
    end
  end

  def python_module_name(%{python_module: python_module}) when is_binary(python_module),
    do: python_module

  def python_module_name(_), do: "unknown"

  @doc false
  def library_name(module, python_module) when is_atom(module) do
    if function_exported?(module, :__snakebridge_library__, 0) do
      module.__snakebridge_library__()
    else
      python_module |> String.split(".") |> List.first()
    end
  end

  def library_name(_module, python_module) do
    python_module |> String.split(".") |> List.first()
  end

  @doc false
  def helper_library(helper) when is_binary(helper) do
    case String.split(helper, ".", parts: 2) do
      [library, _rest] -> library
      _ -> "unknown"
    end
  end

  def helper_library(_), do: "unknown"

  @doc false
  def maybe_put_session_id(payload, nil), do: payload

  def maybe_put_session_id(payload, session_id) when is_binary(session_id) do
    Map.put(payload, "session_id", session_id)
  end

  defp ref_field(ref, "python_module") when is_map(ref),
    do: Map.get(ref, "python_module") || Map.get(ref, :python_module)

  defp ref_field(ref, "library") when is_map(ref),
    do: Map.get(ref, "library") || Map.get(ref, :library)

  defp ref_field(ref, "session_id") when is_map(ref),
    do: Map.get(ref, "session_id") || Map.get(ref, :session_id)

  defp ref_field(_ref, _key), do: nil
end
