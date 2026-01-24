defmodule SnakeBridge.GenerateAllTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Compiler.Pipeline
  alias SnakeBridge.Config
  alias SnakeBridge.Config.Library
  alias SnakeBridge.Introspector

  describe "Introspector.introspect_module/2" do
    @tag :real_python
    test "introspects entire json module" do
      library = %Library{
        name: :json,
        version: :stdlib,
        module_name: Json,
        python_name: "json",
        generate: :all
      }

      assert {:ok, result} = Introspector.introspect_module(library)
      assert is_map(result)
      assert result["module"] == "json"
      assert result["version"] == "2.1"

      # json module should have functions like loads, dumps in namespaces[""]
      namespaces = result["namespaces"]
      assert is_map(namespaces)
      assert Map.has_key?(namespaces, "")

      base_namespace = namespaces[""]
      functions = base_namespace["functions"] || []
      function_names = Enum.map(functions, & &1["name"])
      assert "loads" in function_names
      assert "dumps" in function_names
    end

    @tag :real_python
    test "introspects module with submodules option" do
      library = %Library{
        name: :os,
        version: :stdlib,
        module_name: Os,
        python_name: "os",
        generate: :all,
        submodules: ["path"]
      }

      assert {:ok, result} = Introspector.introspect_module(library, submodules: ["path"])
      assert is_map(result)

      # Should have namespaces
      namespaces = result["namespaces"] || %{}
      # Base module namespace
      assert Map.has_key?(namespaces, "")
    end
  end

  describe "Config.Library generate option" do
    test "defaults to :used" do
      library = %Library{
        name: :test,
        version: "1.0.0",
        module_name: Test,
        python_name: "test"
      }

      assert library.generate == :used
    end

    test "accepts :all option" do
      [library] = Config.parse_libraries([{:test, "1.0.0", generate: :all}])
      assert library.generate == :all
    end

    test "accepts :used option explicitly" do
      [library] = Config.parse_libraries([{:test, "1.0.0", generate: :used}])
      assert library.generate == :used
    end

    test "validates generate option" do
      assert_raise ArgumentError, ~r/generate.*must be.*:all.*:used/i, fn ->
        Config.parse_libraries([{:test, "1.0.0", generate: :invalid}])
      end
    end
  end

  describe "Config.parse_libraries with generate option" do
    test "parses 3-tuple with generate: :all" do
      [library] =
        Config.parse_libraries([
          {:examplelib, "1.0.0", generate: :all, submodules: true}
        ])

      assert library.name == :examplelib
      assert library.version == "1.0.0"
      assert library.generate == :all
      assert library.submodules == true
    end

    test "parses multiple libraries with different generate modes" do
      libraries =
        Config.parse_libraries([
          {:numpy, "1.26.0"},
          {:examplelib, "1.0.0", generate: :all}
        ])

      [numpy, examplelib] = libraries
      assert numpy.generate == :used
      assert examplelib.generate == :all
    end
  end

  describe "Pipeline with generate: :all" do
    @tag :real_python
    test "process_generate_all_library updates manifest with full module symbols" do
      library = %Library{
        name: :json,
        version: :stdlib,
        module_name: Json,
        python_name: "json",
        generate: :all,
        include: [],
        exclude: [],
        submodules: false
      }

      empty_manifest = %{"symbols" => %{}, "classes" => %{}}

      # This calls the private function via the pipeline
      # We'll test it indirectly by checking if symbols are added
      result = Pipeline.test_process_generate_all_library(empty_manifest, library)

      # Should have symbols for json functions
      symbols = result["symbols"] || %{}
      symbol_names = symbols |> Map.values() |> Enum.map(& &1["python_name"])

      assert "loads" in symbol_names
      assert "dumps" in symbol_names
    end
  end
end
