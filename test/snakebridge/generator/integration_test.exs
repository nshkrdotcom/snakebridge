defmodule SnakeBridge.Generator.IntegrationTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Generator.{Introspector, SourceWriter}

  describe "end-to-end generation" do
    @tag :real_python
    test "introspects and generates code for Python math module" do
      # Step 1: Introspect the math module
      assert {:ok, introspection} = Introspector.introspect("math")

      # Verify introspection contains expected data
      assert introspection["module"] == "math"
      assert is_list(introspection["functions"])
      assert length(introspection["functions"]) > 0

      # Find a specific function
      sqrt_func = Enum.find(introspection["functions"], fn f -> f["name"] == "sqrt" end)
      assert sqrt_func != nil

      # Step 2: Generate Elixir source code (returns map of files)
      files = SourceWriter.generate(introspection, module_name: "PythonMath")

      # Verify generated files map
      assert is_map(files)
      assert Map.has_key?(files, "math/math.ex")

      # Verify main source contains expected elements
      main_source = files["math/math.ex"]
      assert main_source =~ "defmodule PythonMath do"
      assert main_source =~ "@moduledoc"
      assert main_source =~ "def sqrt"
      assert main_source =~ "@spec"
      assert main_source =~ "@doc"
    end

    @tag :real_python
    test "generates code for Python json module" do
      assert {:ok, introspection} = Introspector.introspect("json")

      assert introspection["module"] == "json"

      files = SourceWriter.generate(introspection, module_name: "PythonJson")

      # generate/2 now returns a map of files
      assert is_map(files)
      assert Map.has_key?(files, "json/json.ex")

      main_source = files["json/json.ex"]
      assert main_source =~ "defmodule PythonJson do"
      assert main_source =~ "@moduledoc"
    end

    test "handles introspection errors gracefully" do
      # Try to introspect a non-existent module
      assert {:error, error_msg} = Introspector.introspect("this_module_does_not_exist_xyz")
      assert is_binary(error_msg)
      assert error_msg =~ "Failed to import module"
    end

    @tag :real_python
    test "complete workflow with file generation" do
      output_path = Path.join(System.tmp_dir!(), "test_math_module.ex")

      try do
        # Introspect and generate
        {:ok, introspection} = Introspector.introspect("math")

        assert :ok =
                 SourceWriter.generate_file(introspection, output_path, module_name: "TestMath")

        # Verify file was created
        assert File.exists?(output_path)

        # Read and verify content
        content = File.read!(output_path)
        assert content =~ "defmodule TestMath do"
        assert content =~ "@spec"
        assert content =~ "def "
      after
        # Clean up
        File.rm(output_path)
      end
    end
  end

  describe "type mapping integration" do
    test "generates correct typespecs for various Python types" do
      # Mock introspection data with different types
      introspection = %{
        "module" => "test_types",
        "functions" => [
          %{
            "name" => "add_numbers",
            "parameters" => [
              %{"name" => "a", "type" => %{"type" => "int"}},
              %{"name" => "b", "type" => %{"type" => "int"}}
            ],
            "return_type" => %{"type" => "int"},
            "docstring" => %{"summary" => "Add two integers"}
          },
          %{
            "name" => "process_list",
            "parameters" => [
              %{
                "name" => "items",
                "type" => %{
                  "type" => "list",
                  "element_type" => %{"type" => "str"}
                }
              }
            ],
            "return_type" => %{"type" => "list", "element_type" => %{"type" => "str"}},
            "docstring" => %{"summary" => "Process a list of strings"}
          },
          %{
            "name" => "optional_param",
            "parameters" => [
              %{
                "name" => "value",
                "type" => %{
                  "type" => "optional",
                  "inner_type" => %{"type" => "str"}
                }
              }
            ],
            "return_type" => %{"type" => "bool"},
            "docstring" => %{"summary" => "Takes optional string"}
          }
        ]
      }

      files = SourceWriter.generate(introspection, module_name: "TestTypes")

      # Get main module source
      assert source = files["test_types/test_types.ex"]

      # Verify integer types
      assert source =~ "@spec add_numbers(integer(), integer()) :: integer()"

      # Verify list types
      assert source =~ "list(String.t())"

      # Verify optional types (should have | nil)
      assert source =~ "| nil"
    end
  end

  describe "documentation generation" do
    test "generates proper module and function documentation" do
      introspection = %{
        "module" => "example",
        "docstring" => %{
          "summary" => "An example module",
          "description" => "This module demonstrates documentation generation."
        },
        "functions" => [
          %{
            "name" => "greet",
            "parameters" => [
              %{"name" => "name", "type" => %{"type" => "str"}}
            ],
            "return_type" => %{"type" => "str"},
            "docstring" => %{
              "summary" => "Greet a person",
              "params" => [
                %{"name" => "name", "description" => "The person's name"}
              ],
              "returns" => %{"description" => "A greeting message"}
            }
          }
        ]
      }

      files = SourceWriter.generate(introspection, module_name: "Example")
      assert source = files["example/example.ex"]

      # Check module documentation
      assert source =~ "@moduledoc"
      assert source =~ "An example module"
      assert source =~ "This module demonstrates documentation generation."

      # Check function documentation
      assert source =~ "@doc"
      assert source =~ "Greet a person"
      assert source =~ "## Parameters"
      assert source =~ "The person's name"
      assert source =~ "## Returns"
      assert source =~ "A greeting message"
    end
  end

  describe "class generation" do
    test "generates nested modules for Python classes" do
      introspection = %{
        "module" => "mylib",
        "functions" => [],
        "classes" => [
          %{
            "name" => "Calculator",
            "docstring" => %{
              "summary" => "A simple calculator class"
            },
            "methods" => [
              %{
                "name" => "add",
                "parameters" => [
                  %{"name" => "self", "type" => %{"type" => "any"}},
                  %{"name" => "a", "type" => %{"type" => "int"}},
                  %{"name" => "b", "type" => %{"type" => "int"}}
                ],
                "return_type" => %{"type" => "int"},
                "docstring" => %{"summary" => "Add two numbers"}
              }
            ]
          }
        ]
      }

      files = SourceWriter.generate(introspection, module_name: "MyLib")

      # Check class file generation
      assert source = files["mylib/classes/calculator.ex"]
      assert source =~ "defmodule MyLib.Calculator do"
      assert source =~ "@type t() :: reference()"
      assert source =~ "def add"
    end
  end

  describe "options and configuration" do
    test "respects use_snakebridge option" do
      introspection = %{
        "module" => "test",
        "functions" => []
      }

      # With use_snakebridge: true (default)
      files_with = SourceWriter.generate(introspection, use_snakebridge: true)
      source_with = files_with["test/test.ex"]
      assert source_with =~ "use SnakeBridge.Adapter"

      # With use_snakebridge: false
      files_without = SourceWriter.generate(introspection, use_snakebridge: false)
      source_without = files_without["test/test.ex"]
      refute source_without =~ "use SnakeBridge.Adapter"
    end

    test "respects add_python_annotations option" do
      introspection = %{
        "module" => "test",
        "functions" => [
          %{
            "name" => "test_func",
            "parameters" => [],
            "return_type" => %{"type" => "any"},
            "docstring" => %{"summary" => "Test"}
          }
        ]
      }

      # With add_python_annotations: true (default)
      files_with = SourceWriter.generate(introspection, add_python_annotations: true)
      source_with = files_with["test/test.ex"]
      assert source_with =~ "@python_function"

      # With add_python_annotations: false
      files_without = SourceWriter.generate(introspection, add_python_annotations: false)
      source_without = files_without["test/test.ex"]
      refute source_without =~ "@python_function"
    end

    test "uses custom module name" do
      introspection = %{
        "module" => "some.python.module",
        "functions" => []
      }

      files = SourceWriter.generate(introspection, module_name: "My.Custom.Module")
      source = files["some/some.ex"]
      assert source =~ "defmodule My.Custom.Module do"
    end

    test "auto-generates module name from Python module name" do
      introspection = %{
        "module" => "my_python_lib",
        "functions" => []
      }

      files = SourceWriter.generate(introspection)
      source = files["my_python_lib/my_python_lib.ex"]
      assert source =~ "defmodule MyPythonLib do"
    end
  end
end
