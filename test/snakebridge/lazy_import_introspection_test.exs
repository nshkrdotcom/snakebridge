defmodule SnakeBridge.LazyImportIntrospectionTest do
  @moduledoc """
  Tests that introspection correctly handles lazy imports.

  Some Python libraries (like vllm) use __getattr__ for lazy loading.
  Classes declared in __all__ aren't visible to inspect.getmembers()
  until explicitly accessed. The introspector must handle this by
  iterating over __all__ and accessing those names directly.
  """
  use ExUnit.Case, async: false

  @fixtures_path Path.expand("../fixtures/python", __DIR__)

  setup do
    # Set up PYTHONPATH in introspector config
    original_config = Application.get_env(:snakebridge, :introspector, [])

    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    pythonpath =
      [@fixtures_path, System.get_env("PYTHONPATH")]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    Application.put_env(:snakebridge, :introspector, env: %{"PYTHONPATH" => pythonpath})

    on_exit(fn ->
      Application.put_env(:snakebridge, :introspector, original_config)
    end)

    :ok
  end

  describe "lazy import handling" do
    test "discovers lazy-loaded classes from __all__" do
      library = %{name: :fixture_lazy_import, python_name: "fixture_lazy_import"}
      {:ok, result} = SnakeBridge.Introspector.introspect_module(library)

      # Get class names from introspection result
      class_names =
        result
        |> Map.get("namespaces", %{})
        |> Map.get("", %{})
        |> Map.get("classes", [])
        |> Enum.map(& &1["name"])

      # LazyClass and LazyParams should be discovered even though they're lazy-loaded
      assert "LazyClass" in class_names,
             "LazyClass should be discovered via __all__ lazy import handling. Got: #{inspect(class_names)}"

      assert "LazyParams" in class_names,
             "LazyParams should be discovered via __all__ lazy import handling. Got: #{inspect(class_names)}"
    end

    test "discovers eager functions alongside lazy classes" do
      library = %{name: :fixture_lazy_import, python_name: "fixture_lazy_import"}
      {:ok, result} = SnakeBridge.Introspector.introspect_module(library)

      function_names =
        result
        |> Map.get("namespaces", %{})
        |> Map.get("", %{})
        |> Map.get("functions", [])
        |> Enum.map(& &1["name"])

      # eager_function should be found via normal introspection
      assert "eager_function" in function_names,
             "Eager functions should still be discovered normally. Got: #{inspect(function_names)}"
    end

    test "introspects lazy-loaded class methods" do
      library = %{name: :fixture_lazy_import, python_name: "fixture_lazy_import"}
      {:ok, result} = SnakeBridge.Introspector.introspect_module(library)

      classes =
        result
        |> Map.get("namespaces", %{})
        |> Map.get("", %{})
        |> Map.get("classes", [])

      lazy_class = Enum.find(classes, &(&1["name"] == "LazyClass"))
      assert lazy_class, "LazyClass should be found"

      method_names = Enum.map(lazy_class["methods"] || [], & &1["name"])

      # Check that methods are introspected
      assert "process" in method_names,
             "LazyClass.process method should be introspected. Got: #{inspect(method_names)}"

      assert "get_value" in method_names,
             "LazyClass.get_value method should be introspected. Got: #{inspect(method_names)}"
    end

    test "introspects lazy-loaded class constructor parameters" do
      library = %{name: :fixture_lazy_import, python_name: "fixture_lazy_import"}
      {:ok, result} = SnakeBridge.Introspector.introspect_module(library)

      classes =
        result
        |> Map.get("namespaces", %{})
        |> Map.get("", %{})
        |> Map.get("classes", [])

      lazy_class = Enum.find(classes, &(&1["name"] == "LazyClass"))
      assert lazy_class, "LazyClass should be found"

      # Check __init__ method has parameters (constructor is in methods list)
      methods = lazy_class["methods"] || []
      init_method = Enum.find(methods, &(&1["name"] == "__init__"))

      assert init_method,
             "__init__ method should be introspected. Methods: #{inspect(Enum.map(methods, & &1["name"]))}"

      param_names = Enum.map(init_method["parameters"] || [], & &1["name"])

      assert "name" in param_names,
             "Constructor should have 'name' parameter. Got: #{inspect(param_names)}"

      assert "value" in param_names,
             "Constructor should have 'value' parameter. Got: #{inspect(param_names)}"
    end

    test "introspects dataclass lazy-loaded class" do
      library = %{name: :fixture_lazy_import, python_name: "fixture_lazy_import"}
      {:ok, result} = SnakeBridge.Introspector.introspect_module(library)

      classes =
        result
        |> Map.get("namespaces", %{})
        |> Map.get("", %{})
        |> Map.get("classes", [])

      lazy_params = Enum.find(classes, &(&1["name"] == "LazyParams"))
      assert lazy_params, "LazyParams should be found"

      method_names = Enum.map(lazy_params["methods"] || [], & &1["name"])

      assert "clone" in method_names,
             "LazyParams.clone method should be introspected. Got: #{inspect(method_names)}"
    end
  end
end
