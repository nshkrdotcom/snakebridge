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

    test "class with optional __init__ args generates faithful positional arities" do
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

      assert source =~ "def new(path) do"
      assert source =~ "def new(path, opts) when"
      assert source =~ "def new(path, readonly) do"
      assert source =~ "def new(path, readonly, opts) when"
      assert source =~ "call_class(__MODULE__, :__init__, [path], [])"
      assert source =~ "call_class(__MODULE__, :__init__, [path, readonly], opts)"
      refute source =~ "List.wrap(args)"
    end

    test "RLM-style constructor keeps one required parameter and seven Python defaults optional" do
      defaults = [
        {"max_iters", "20"},
        {"max_llm_calls", "50"},
        {"max_output_chars", "10000"},
        {"verbose", "False"},
        {"tools", "None"},
        {"sub_lm", "None"},
        {"interpreter_factory", "PythonInterpreter"}
      ]

      params =
        [%{"name" => "signature", "kind" => "POSITIONAL_OR_KEYWORD"}] ++
          Enum.map(defaults, fn {name, default} ->
            %{"name" => name, "kind" => "POSITIONAL_OR_KEYWORD", "default" => default}
          end)

      class_info = %{
        "name" => "RLM",
        "python_module" => "dspy.predict",
        "methods" => [%{"name" => "__init__", "parameters" => params}],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :dspy,
        python_name: "dspy",
        module_name: Dspy
      }

      source = Generator.render_class(class_info, library)

      assert source =~ "def new(signature) do"
      assert source =~ "def new(signature, opts) when"
      assert source =~ "def new(signature, max_iters) do"

      assert source =~
               "def new(signature, max_iters, max_llm_calls, max_output_chars, verbose, tools, sub_lm, interpreter_factory) do"

      assert source =~ "call_class(__MODULE__, :__init__, [signature], [])"

      refute source =~
               "def new(signature, max_iters, max_llm_calls, max_output_chars, verbose, tools, sub_lm, interpreter_factory, opts \\ [])"
    end

    test "class methods with Python defaults generate the same arity family" do
      class_info = %{
        "name" => "Worker",
        "python_module" => "mylib",
        "methods" => [
          %{"name" => "__init__", "parameters" => []},
          %{
            "name" => "run",
            "parameters" => [
              %{"name" => "self", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "limit", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "10"}
            ],
            "return_type" => %{"type" => "any"}
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

      assert source =~ "def run(ref, value) do"
      assert source =~ "def run(ref, value, opts) when"
      assert source =~ "def run(ref, value, limit) do"
      assert source =~ "def run(ref, value, limit, opts) when"
      assert source =~ "call_method(ref, :run, [value], [])"
      assert source =~ "call_method(ref, :run, [value, limit], opts)"
    end

    test "class default arities validate required keyword-only params without an undefined opts variable" do
      class_info = %{
        "name" => "ConfiguredWorker",
        "python_module" => "mylib",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "limit", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "10"},
              %{"name" => "mode", "kind" => "KEYWORD_ONLY"}
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

      assert source =~ "def new(value) do"
      assert source =~ "kw_keys = [] |> Keyword.keys()"
      assert source =~ "def new(value, opts) when"
      assert source =~ "kw_keys = opts |> Keyword.keys()"
    end
  end
end
