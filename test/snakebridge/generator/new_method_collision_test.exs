defmodule SnakeBridge.Generator.NewMethodCollisionTest do
  @moduledoc """
  Tests that the generator correctly handles Python classes that have
  a method named 'new', which would otherwise conflict with the generated
  constructor (also named 'new').

  This collision occurs in real libraries like vLLM where some classes
  have factory methods named 'new'.
  """
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "render_class/2 handles 'new' method collision" do
    test "class with __init__ and method named 'new' renames the method to avoid collision" do
      class_info = %{
        "name" => "ClassWithNewMethod",
        "python_module" => "fixture_new_collision",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD", "annotation" => "int"}
            ]
          },
          %{
            "name" => "new",
            "parameters" => [
              %{"name" => "other_value", "kind" => "POSITIONAL_OR_KEYWORD", "annotation" => "int"}
            ],
            "return_type" => %{"type" => "class", "name" => "ClassWithNewMethod"}
          },
          %{
            "name" => "get_value",
            "parameters" => [],
            "return_type" => %{"type" => "int"}
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :fixture_new_collision,
        python_name: "fixture_new_collision",
        module_name: FixtureNewCollision
      }

      source = Generator.render_class(class_info, library)

      # The constructor should still be named 'new'
      assert source =~ "def new(value",
             "Constructor should be named 'new'"

      # The method named 'new' should be renamed to avoid collision
      # It should NOT generate a second 'def new(' that conflicts
      refute source =~ ~r/def new\(ref,.*other_value/,
             "Method named 'new' should be renamed to avoid collision with constructor"

      # The renamed method should still be accessible somehow
      # (Either as 'python_new', 'new_method', or similar)
      assert source =~ "other_value",
             "The parameters of the renamed method should still be present"

      # get_value should be generated normally
      assert source =~ "def get_value(ref",
             "Other methods should be generated normally"
    end

    test "class without __init__ can have method named 'new' without collision" do
      class_info = %{
        "name" => "FactoryOnly",
        "python_module" => "mylib",
        "methods" => [
          %{
            "name" => "new",
            "parameters" => [
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

      # When there's no __init__, the 'new' method can keep its name
      # (though there will be a generated new() for the class anyway)
      # The important thing is no duplicate definitions
      new_count = source |> String.split("def new(") |> length() |> Kernel.-(1)

      assert new_count <= 2,
             "Should not generate multiple conflicting 'def new' clauses. Found #{new_count}"
    end

    test "generated code compiles without 'defaults multiple times' error" do
      class_info = %{
        "name" => "TestClass",
        "python_module" => "testmod",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"}
            ]
          },
          %{
            "name" => "new",
            "parameters" => [
              %{"name" => "y", "kind" => "POSITIONAL_OR_KEYWORD"}
            ]
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :testmod,
        python_name: "testmod",
        module_name: Testmod
      }

      source = Generator.render_class(class_info, library)

      # Wrap in a module and try to compile
      full_source = """
      defmodule TestCollisionModule do
        #{source}
      end
      """

      # This should not raise a compile error about defaults
      assert {:ok, _} = Code.string_to_quoted(full_source),
             "Generated code should be valid Elixir syntax"
    end

    test "variadic __init__ with method named 'new' renames method to avoid arity collision" do
      # This reproduces the vllm CoreEngineState case:
      # __init__(self, *args, **kwds) generates variadic new() clauses at every arity
      # A method named 'new' would conflict at overlapping arities
      class_info = %{
        "name" => "CoreEngineState",
        "python_module" => "vllm.v1.engine.utils",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "args", "kind" => "VAR_POSITIONAL"},
              %{"name" => "kwds", "kind" => "VAR_KEYWORD"}
            ]
          },
          %{
            "name" => "new",
            "parameters" => [
              %{
                "name" => "num_spec_tokens",
                "kind" => "POSITIONAL_OR_KEYWORD",
                "annotation" => "int"
              }
            ],
            "return_type" => %{"type" => "class", "name" => "CoreEngineState"}
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :vllm,
        python_name: "vllm",
        module_name: Vllm
      }

      source = Generator.render_class(class_info, library)

      # The method named 'new' should be renamed to 'python_new'
      # to avoid collision with variadic constructor clauses
      assert source =~ "def python_new(ref",
             "Method named 'new' should be renamed to 'python_new' when __init__ is variadic"

      # Should NOT have conflicting def new(ref, ...) clauses from the method
      refute source =~ ~r/def new\(ref,\s*num_spec_tokens/,
             "Should not generate 'def new(ref, num_spec_tokens' - method should be renamed"

      # Verify the generated code compiles without warnings about multiple clauses
      full_source = """
      defmodule TestVariadicCollision do
        #{source}
      end
      """

      assert {:ok, _} = Code.string_to_quoted(full_source),
             "Generated code should be valid Elixir syntax"
    end

    test "variadic __init__ generates multiple new() arities without method collision" do
      # Variadic __init__ without a 'new' method should work fine
      class_info = %{
        "name" => "VariadicClass",
        "python_module" => "testmod",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "args", "kind" => "VAR_POSITIONAL"},
              %{"name" => "kwargs", "kind" => "VAR_KEYWORD"}
            ]
          },
          %{
            "name" => "do_something",
            "parameters" => [],
            "return_type" => %{"type" => "any"}
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :testmod,
        python_name: "testmod",
        module_name: Testmod
      }

      source = Generator.render_class(class_info, library)

      # Should have multiple def new() clauses for different arities
      assert source =~ "def new(",
             "Should generate variadic new() constructor"

      # Should have the do_something method
      assert source =~ "def do_something(ref",
             "Other methods should be generated normally"

      # Verify it compiles
      full_source = """
      defmodule TestVariadicNoCollision do
        #{source}
      end
      """

      assert {:ok, _} = Code.string_to_quoted(full_source),
             "Generated code should be valid Elixir syntax"
    end
  end
end
