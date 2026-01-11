defmodule SnakeBridge.Generator.ClassConstructorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "render_class/2 generates correct constructors" do
    test "class with no __init__ args generates new/0 or new/1 with opts" do
      class_info = %{
        "name" => "Empty",
        "python_module" => "mylib",
        "methods" => [
          %{"name" => "__init__", "parameters" => []}
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :mylib,
        python_name: "mylib",
        module_name: Mylib
      }

      source = Generator.render_class(class_info, library)

      # Should generate new() or new(opts \\ []) depending on design decision
      assert source =~ "def new("
      refute source =~ "def new(arg, opts"
    end

    test "class with multiple required __init__ args generates correct new/N" do
      class_info = %{
        "name" => "Point",
        "python_module" => "geometry",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "y", "kind" => "POSITIONAL_OR_KEYWORD"}
            ]
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :geometry,
        python_name: "geometry",
        module_name: Geometry
      }

      source = Generator.render_class(class_info, library)

      assert source =~ "def new(x, y"
      assert source =~ "call_class(__MODULE__, :__init__, [x, y]"
    end

    test "class __init__ skips self parameter" do
      class_info = %{
        "name" => "Widget",
        "python_module" => "mylib",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "self", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"}
            ]
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :mylib,
        python_name: "mylib",
        module_name: Mylib
      }

      source = Generator.render_class(class_info, library)

      assert source =~ "def new(value"
      refute source =~ "def new(self"
    end

    test "class with optional __init__ args generates new with opts" do
      class_info = %{
        "name" => "Config",
        "python_module" => "mylib",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "path", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "readonly", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "False"}
            ]
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :mylib,
        python_name: "mylib",
        module_name: Mylib
      }

      source = Generator.render_class(class_info, library)

      assert source =~ "def new(path, args, opts \\\\ [])"
      assert source =~ "call_class(__MODULE__, :__init__, [path] ++ List.wrap(args), opts)"
    end
  end
end
