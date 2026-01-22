defmodule SnakeBridge.Generator.ClassHeredocTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator
  alias SnakeBridge.Generator.Class, as: ClassGenerator

  defp base_library(module_name \\ Mylib) do
    %SnakeBridge.Config.Library{
      name: :mylib,
      python_name: "mylib",
      module_name: module_name
    }
  end

  defp base_class_info(overrides) do
    Map.merge(
      %{
        "name" => "Widget",
        "python_module" => "mylib",
        "docstring" => "Widget docs.",
        "methods" => [],
        "attributes" => []
      },
      overrides
    )
  end

  test "render_class/2 includes @moduledoc from class docstring" do
    class_info = base_class_info(%{"docstring" => "Class docs."})
    source = Generator.render_class(class_info, base_library())

    assert source =~ "@moduledoc"
    assert source =~ "Class docs."
  end

  test "render_class_standalone/3 includes @moduledoc from class docstring" do
    class_info = base_class_info(%{"docstring" => "Standalone docs."})

    source =
      ClassGenerator.render_class_standalone(class_info, base_library(), "Mylib.Standalone")

    assert source =~ "@moduledoc"
    assert source =~ "Standalone docs."
  end

  test "constructor includes @doc from __init__ docstring" do
    init_method = %{
      "name" => "__init__",
      "docstring" => "Init docs.",
      "parameters" => [%{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"}]
    }

    class_info = base_class_info(%{"methods" => [init_method]})
    source = Generator.render_class(class_info, base_library())

    assert Regex.match?(~r/@doc\s+\"\"\".*Init docs.*\"\"\"\s*@spec new/s, source)
  end

  test "methods include @doc from method docstring" do
    method = %{
      "name" => "compute",
      "docstring" => "Compute docs.",
      "parameters" => [
        %{"name" => "self", "kind" => "POSITIONAL_OR_KEYWORD"},
        %{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"}
      ],
      "return_type" => %{"type" => "int"}
    }

    class_info = base_class_info(%{"methods" => [method]})
    source = Generator.render_class(class_info, base_library())

    assert Regex.match?(~r/@doc\s+\"\"\".*Compute docs.*\"\"\"\s*@spec compute/s, source)
  end

  test "handles nil docstrings gracefully and compiles without warnings" do
    init_method = %{"name" => "__init__", "docstring" => nil, "parameters" => []}

    method = %{
      "name" => "ping",
      "docstring" => nil,
      "parameters" => [%{"name" => "self", "kind" => "POSITIONAL_OR_KEYWORD"}],
      "return_type" => %{"type" => "int"}
    }

    class_info =
      base_class_info(%{
        "name" => "NilDocs",
        "docstring" => nil,
        "methods" => [init_method, method]
      })

    source = Generator.render_class(class_info, base_library())

    assert source =~ "@moduledoc"
    assert source =~ "Wrapper for Python class NilDocs."
    assert source =~ "Constructs `NilDocs`."
    assert source =~ "Python method `NilDocs.ping`."

    warnings = ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.compile_string(source) end)
    assert warnings == ""
  end

  test "handles empty docstrings gracefully" do
    init_method = %{"name" => "__init__", "docstring" => "", "parameters" => []}

    method = %{
      "name" => "ping",
      "docstring" => "",
      "parameters" => [%{"name" => "self", "kind" => "POSITIONAL_OR_KEYWORD"}]
    }

    class_info = base_class_info(%{"docstring" => "", "methods" => [init_method, method]})
    source = Generator.render_class(class_info, base_library())

    assert source =~ "@moduledoc"
    assert source =~ "Wrapper for Python class Widget."
    assert source =~ "Constructs `Widget`."
    assert source =~ "Python method `Widget.ping`."
  end

  test "variadic constructor and method include @doc when docstring present" do
    init_method = %{
      "name" => "__init__",
      "docstring" => "Variadic init.",
      "parameters" => [],
      "signature_available" => false
    }

    method = %{
      "name" => "run",
      "docstring" => "Variadic method.",
      "parameters" => [],
      "signature_available" => false
    }

    class_info = base_class_info(%{"methods" => [init_method, method]})
    source = Generator.render_class(class_info, base_library())

    assert source =~ "Variadic init."
    assert source =~ "Variadic method."
  end

  test "generated code compiles without warnings via Code.compile_string/1" do
    unique = System.unique_integer([:positive])
    library_module = Module.concat(["HeredocLib", "Test#{unique}"])
    class_module = Module.concat([library_module, "Widget"])
    library = base_library(library_module)

    init_method = %{
      "name" => "__init__",
      "docstring" => "Init docs.",
      "parameters" => [%{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"}]
    }

    method = %{
      "name" => "compute",
      "docstring" => "Compute docs.",
      "parameters" => [
        %{"name" => "self", "kind" => "POSITIONAL_OR_KEYWORD"},
        %{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"}
      ],
      "return_type" => %{"type" => "int"}
    }

    class_info =
      base_class_info(%{
        "name" => "Widget#{unique}",
        "docstring" => "Class docs.",
        "methods" => [init_method, method]
      })

    source = ClassGenerator.render_class_standalone(class_info, library, class_module)
    warnings = ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.compile_string(source) end)

    assert warnings == ""
  end
end
