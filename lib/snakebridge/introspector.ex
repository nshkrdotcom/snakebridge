defmodule SnakeBridge.Introspector do
  @moduledoc """
  Introspects Python functions using the Snakepit-configured runtime.
  """

  alias SnakeBridge.IntrospectionError

  @type function_name :: atom() | String.t()

  @spec introspect(SnakeBridge.Config.Library.t() | map(), [function_name()]) ::
          {:ok, list()} | {:error, term()}
  def introspect(library, functions) when is_list(functions) do
    introspect(library, functions, nil)
  end

  @spec introspect(SnakeBridge.Config.Library.t() | map(), [function_name()], String.t() | nil) ::
          {:ok, list()} | {:error, term()}
  def introspect(library, functions, python_module) when is_list(functions) do
    start_time = System.monotonic_time()
    library_label = library_label(library)
    SnakeBridge.Telemetry.introspect_start(library_label, length(functions))
    python_name = python_module || library_python_name(library)
    functions_json = Jason.encode!(Enum.map(functions, &to_string/1))

    result =
      case python_runner().run(
             introspection_script(),
             [python_name, functions_json],
             runner_opts()
           ) do
        {:ok, output} -> parse_output(output)
        {:error, {:python_exit, _status, output}} -> handle_python_error(output, python_name)
        {:error, reason} -> {:error, reason}
      end

    symbols =
      case result do
        {:ok, results} when is_list(results) -> length(results)
        _ -> 0
      end

    SnakeBridge.Telemetry.introspect_stop(
      start_time,
      library_label,
      symbols,
      0,
      System.monotonic_time() - start_time
    )

    result
  end

  @spec introspect_batch([
          {SnakeBridge.Config.Library.t() | map(), String.t(), [function_name()]}
        ]) ::
          list(
            {SnakeBridge.Config.Library.t() | map(), {:ok, list()} | {:error, term()}, String.t()}
          )
  def introspect_batch(libs_and_functions) when is_list(libs_and_functions) do
    config = Application.get_env(:snakebridge, :introspector, [])
    max_concurrency = Keyword.get(config, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(config, :timeout, 30_000)

    results =
      libs_and_functions
      |> Task.async_stream(
        fn {library, python_module, functions} ->
          {library, introspect(library, functions, python_module), python_module}
        end,
        max_concurrency: max_concurrency,
        timeout: timeout
      )
      |> Enum.to_list()

    libs_and_functions
    |> Enum.zip(results)
    |> Enum.map(fn
      {{_library, _python_module, _functions}, {:ok, result}} ->
        result

      {{library, python_module, functions}, {:exit, reason}} ->
        {library, {:error, batch_error(library, python_module, functions, reason)}, python_module}

      {{library, python_module, functions}, {:error, reason}} ->
        {library, {:error, batch_error(library, python_module, functions, reason)}, python_module}
    end)
  end

  defp library_python_name(%{python_name: python_name}) when is_binary(python_name),
    do: python_name

  defp library_python_name(%{name: name}) when is_atom(name), do: Atom.to_string(name)
  defp library_python_name(name) when is_binary(name), do: name
  defp library_python_name(_), do: "unknown"

  defp python_runner do
    Application.get_env(:snakebridge, :python_runner, SnakeBridge.PythonRunner.System)
  end

  defp library_label(%{name: name}) when is_atom(name), do: name
  defp library_label(name) when is_atom(name), do: name
  defp library_label(_), do: :unknown

  defp runner_opts do
    config = Application.get_env(:snakebridge, :introspector, [])
    Keyword.take(config, [:timeout, :env, :cd])
  end

  defp parse_output(output) do
    case Jason.decode(output) do
      {:ok, results} when is_list(results) -> {:ok, results}
      {:ok, %{"error" => error}} -> {:error, error}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end

  defp introspection_script do
    ~S"""
    import importlib
    import inspect
    import json
    import sys
    import typing

    def _format_annotation(annotation):
        if annotation is inspect.Signature.empty:
            return None
        if hasattr(annotation, "__name__"):
            return annotation.__name__
        return str(annotation)

    def _type_to_dict(annotation):
        if annotation is None or annotation is type(None):
            return {"type": "none"}
        if annotation is inspect.Signature.empty:
            return {"type": "any"}
        if annotation is typing.Any:
            return {"type": "any"}

        if annotation is int:
            return {"type": "int"}
        if annotation is float:
            return {"type": "float"}
        if annotation is str:
            return {"type": "str"}
        if annotation is bool:
            return {"type": "bool"}
        if annotation is bytes:
            return {"type": "bytes"}
        if annotation is bytearray:
            return {"type": "bytearray"}
        if annotation is list:
            return {"type": "list"}
        if annotation is dict:
            return {"type": "dict"}
        if annotation is tuple:
            return {"type": "tuple"}
        if annotation is set:
            return {"type": "set"}
        if annotation is frozenset:
            return {"type": "frozenset"}

        origin = typing.get_origin(annotation)
        args = typing.get_args(annotation)

        if origin is not None:
            if origin is list:
                return {"type": "list", "element_type": _type_to_dict(args[0])} if args else {"type": "list"}
            if origin is dict:
                if len(args) == 2:
                    return {
                        "type": "dict",
                        "key_type": _type_to_dict(args[0]),
                        "value_type": _type_to_dict(args[1])
                    }
                return {"type": "dict"}
            if origin is tuple:
                if args:
                    return {"type": "tuple", "element_types": [_type_to_dict(arg) for arg in args]}
                return {"type": "tuple"}
            if origin is set:
                return {"type": "set", "element_type": _type_to_dict(args[0])} if args else {"type": "set"}
            if origin is frozenset:
                return {
                    "type": "frozenset",
                    "element_type": _type_to_dict(args[0]) if args else {"type": "any"}
                }
            if origin is typing.Union:
                union_types = [_type_to_dict(arg) for arg in args]
                none_count = sum(1 for ut in union_types if ut.get("type") == "none")
                if none_count == 1 and len(union_types) == 2:
                    other_type = next(ut for ut in union_types if ut.get("type") != "none")
                    return {"type": "optional", "inner_type": other_type}
                return {"type": "union", "types": union_types}

        if inspect.isclass(annotation):
            name = annotation.__name__
            module = annotation.__module__
            type_name = name.lower()

            if "numpy" in module and "ndarray" in type_name:
                return {"type": "numpy.ndarray"}
            if "numpy" in module and "dtype" in type_name:
                return {"type": "numpy.dtype"}
            if "torch" in module and "tensor" in name:
                return {"type": "torch.Tensor"}
            if "torch" in module and "dtype" in type_name:
                return {"type": "torch.dtype"}
            if "pandas" in module and "dataframe" in type_name:
                return {"type": "pandas.DataFrame"}
            if "pandas" in module and "series" in type_name:
                return {"type": "pandas.Series"}

            return {"type": "class", "name": name, "module": module}

        return {"type": "any", "raw": str(annotation)}

    def _param_info(param, type_hint=None):
        info = {"name": param.name, "kind": param.kind.name}
        if param.default is not inspect.Parameter.empty:
            info["default"] = repr(param.default)
        if param.annotation is not inspect.Parameter.empty:
            info["annotation"] = _format_annotation(param.annotation)

        type_annotation = type_hint if type_hint is not None else param.annotation
        info["type"] = _type_to_dict(type_annotation)
        return info

    def _introspect_callable(name, obj, module_name):
        info = {
            "name": name,
            "callable": callable(obj),
            "module": module_name,
            "python_module": module_name
        }
        try:
            sig = inspect.signature(obj)
            try:
                type_hints = typing.get_type_hints(obj)
            except Exception:
                type_hints = {}

            info["parameters"] = [
                _param_info(p, type_hints.get(p.name))
                for p in sig.parameters.values()
            ]
            if sig.return_annotation is not inspect.Signature.empty:
                info["return_annotation"] = _format_annotation(sig.return_annotation)
            info["return_type"] = _type_to_dict(type_hints.get("return", sig.return_annotation))
        except (ValueError, TypeError):
            info["parameters"] = []

        doc = inspect.getdoc(obj)
        if doc:
            info["docstring"] = doc[:8000]
        return info

    def _introspect_class(name, cls):
        methods = []
        for method_name, method in inspect.getmembers(cls, predicate=callable):
            if method_name.startswith("__") and method_name not in ["__init__"]:
                continue
            try:
                sig = inspect.signature(method)
                try:
                    type_hints = typing.get_type_hints(method)
                except Exception:
                    type_hints = {}

                params = [
                    _param_info(p, type_hints.get(p.name))
                    for p in sig.parameters.values()
                    if p.name != "self"
                ]

                return_type = _type_to_dict(type_hints.get("return", sig.return_annotation))
            except (ValueError, TypeError):
                params = []
                return_type = {"type": "any"}
            methods.append({
                "name": method_name,
                "parameters": params,
                "docstring": inspect.getdoc(method) or "",
                "return_type": return_type
            })

        attributes = []
        for attr_name, value in inspect.getmembers(cls):
            if attr_name.startswith("__"):
                continue
            if callable(value):
                continue
            attributes.append(attr_name)

        return {
            "name": name,
            "type": "class",
            "python_module": cls.__module__,
            "docstring": inspect.getdoc(cls) or "",
            "methods": methods,
            "attributes": attributes
        }

    if __name__ == "__main__":
        module_name = sys.argv[1]
        symbols = json.loads(sys.argv[2])
        module = importlib.import_module(module_name)

        results = []
        for name in symbols:
            obj = getattr(module, name, None)
            if obj is None:
                results.append({"name": name, "error": "not_found"})
                continue

            if inspect.isclass(obj):
                results.append(_introspect_class(name, obj))
            else:
                results.append(_introspect_callable(name, obj, module_name))

        print(json.dumps(results))
    """
  end

  defp handle_python_error(output, package) do
    {:error, IntrospectionError.from_python_output(output, package)}
  end

  defp batch_error(library, python_module, functions, reason) do
    %{
      type: :introspection_batch_failed,
      library: library_label(library),
      python_module: python_module,
      functions: functions,
      reason: reason
    }
  end
end
