defmodule SnakeBridge.Introspector do
  @moduledoc """
  Introspects Python functions using the Snakepit-configured runtime.
  """

  @type function_name :: atom() | String.t()

  @spec introspect(SnakeBridge.Config.Library.t() | map(), [function_name()]) ::
          {:ok, list()} | {:error, term()}
  def introspect(library, functions) when is_list(functions) do
    introspect(library, functions, nil)
  end

  @spec introspect(SnakeBridge.Config.Library.t() | map(), [function_name()], String.t() | nil) ::
          {:ok, list()} | {:error, term()}
  def introspect(library, functions, python_module) when is_list(functions) do
    python_name = python_module || library_python_name(library)
    functions_json = Jason.encode!(Enum.map(functions, &to_string/1))

    case python_runner().run(introspection_script(), [python_name, functions_json], runner_opts()) do
      {:ok, output} -> parse_output(output)
      {:error, reason} -> {:error, reason}
    end
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

    libs_and_functions
    |> Task.async_stream(
      fn {library, python_module, functions} ->
        {library, introspect(library, functions, python_module), python_module}
      end,
      max_concurrency: max_concurrency,
      timeout: timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp library_python_name(%{python_name: python_name}) when is_binary(python_name),
    do: python_name

  defp library_python_name(%{name: name}) when is_atom(name), do: Atom.to_string(name)
  defp library_python_name(name) when is_binary(name), do: name
  defp library_python_name(_), do: "unknown"

  defp python_runner do
    Application.get_env(:snakebridge, :python_runner, SnakeBridge.PythonRunner.System)
  end

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

    def _format_annotation(annotation):
        if annotation is inspect.Signature.empty:
            return None
        if hasattr(annotation, "__name__"):
            return annotation.__name__
        return str(annotation)

    def _param_info(param):
        info = {"name": param.name, "kind": param.kind.name}
        if param.default is not inspect.Parameter.empty:
            info["default"] = repr(param.default)
        if param.annotation is not inspect.Parameter.empty:
            info["annotation"] = _format_annotation(param.annotation)
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
            info["parameters"] = [_param_info(p) for p in sig.parameters.values()]
            if sig.return_annotation is not inspect.Signature.empty:
                info["return_annotation"] = _format_annotation(sig.return_annotation)
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
                params = [_param_info(p) for p in sig.parameters.values() if p.name != "self"]
            except (ValueError, TypeError):
                params = []
            methods.append({
                "name": method_name,
                "parameters": params,
                "docstring": inspect.getdoc(method) or ""
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
end
