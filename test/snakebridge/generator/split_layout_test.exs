defmodule SnakeBridge.Generator.SplitLayoutTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Config.Library
  alias SnakeBridge.Generator

  @moduletag :tmp_dir

  describe "generate_library/4 with split layout" do
    test "creates directory structure for functions", %{tmp_dir: tmp_dir} do
      library = %Library{
        name: :examplelib,
        python_name: "examplelib",
        module_name: Examplelib,
        version: "3.0.0"
      }

      functions = [
        %{"name" => "configure", "python_module" => "examplelib", "parameters" => []},
        %{"name" => "predict", "python_module" => "examplelib.predict", "parameters" => []}
      ]

      config = %SnakeBridge.Config{
        generated_dir: tmp_dir,
        generated_layout: :split,
        libraries: [library]
      }

      :ok = Generator.generate_library(library, functions, [], config)

      # Root module file should exist
      assert File.exists?(Path.join(tmp_dir, "examplelib/__init__.ex"))
      # Submodule file should exist
      assert File.exists?(Path.join(tmp_dir, "examplelib/predict/__init__.ex"))
    end

    test "creates class files as separate .ex files", %{tmp_dir: tmp_dir} do
      library = %Library{
        name: :examplelib,
        python_name: "examplelib",
        module_name: Examplelib,
        version: "3.0.0"
      }

      classes = [
        %{
          "name" => "Module",
          "python_module" => "examplelib",
          "methods" => [],
          "attributes" => []
        },
        %{
          "name" => "Predict",
          "python_module" => "examplelib.predict",
          "methods" => [],
          "attributes" => []
        }
      ]

      config = %SnakeBridge.Config{
        generated_dir: tmp_dir,
        generated_layout: :split,
        libraries: [library]
      }

      :ok = Generator.generate_library(library, [], classes, config)

      # Class files should exist
      assert File.exists?(Path.join(tmp_dir, "examplelib/__init__.ex"))
      assert File.exists?(Path.join(tmp_dir, "examplelib/module.ex"))
      assert File.exists?(Path.join(tmp_dir, "examplelib/predict/predict.ex"))
      assert File.exists?(Path.join(tmp_dir, "examplelib/predict/__init__.ex"))
    end

    test "each module definition appears in exactly one file", %{tmp_dir: tmp_dir} do
      library = %Library{
        name: :examplelib,
        python_name: "examplelib",
        module_name: Examplelib,
        version: "3.0.0"
      }

      functions = [
        %{"name" => "configure", "python_module" => "examplelib", "parameters" => []},
        %{"name" => "predict", "python_module" => "examplelib.predict", "parameters" => []}
      ]

      classes = [
        %{
          "name" => "Predict",
          "module" => "Examplelib.PredictClass",
          "python_module" => "examplelib.predict",
          "methods" => [],
          "attributes" => []
        }
      ]

      config = %SnakeBridge.Config{
        generated_dir: tmp_dir,
        generated_layout: :split,
        libraries: [library]
      }

      :ok = Generator.generate_library(library, functions, classes, config)

      # Read all generated files
      files = Path.wildcard(Path.join([tmp_dir, "**", "*.ex"]))
      assert length(files) >= 2

      # Parse and check for no duplicate module definitions
      module_defs = collect_module_definitions(files)

      assert no_duplicates?(module_defs),
             "Duplicate module definitions found: #{inspect(module_defs)}"
    end

    test "generated files contain correct module names", %{tmp_dir: tmp_dir} do
      library = %Library{
        name: :examplelib,
        python_name: "examplelib",
        module_name: Examplelib,
        version: "3.0.0"
      }

      functions = [
        %{"name" => "configure", "python_module" => "examplelib", "parameters" => []}
      ]

      config = %SnakeBridge.Config{
        generated_dir: tmp_dir,
        generated_layout: :split,
        libraries: [library]
      }

      :ok = Generator.generate_library(library, functions, [], config)

      content = File.read!(Path.join(tmp_dir, "examplelib/__init__.ex"))
      assert content =~ "defmodule Examplelib do"
      assert content =~ "def __snakebridge_python_name__, do: \"examplelib\""
    end

    test "registry entry contains all generated files", %{tmp_dir: tmp_dir} do
      library = %Library{
        name: :test_lib,
        python_name: "test_lib",
        module_name: TestLib,
        version: "1.0.0"
      }

      functions = [
        %{"name" => "func1", "python_module" => "test_lib", "parameters" => []},
        %{"name" => "func2", "python_module" => "test_lib.sub", "parameters" => []}
      ]

      config = %SnakeBridge.Config{
        generated_dir: tmp_dir,
        generated_layout: :split,
        libraries: [library]
      }

      :ok = Generator.generate_library(library, functions, [], config)

      # Check registry has multiple files
      entry = SnakeBridge.Registry.get("test_lib")
      assert entry != nil
      assert is_list(entry.files)
      assert length(entry.files) >= 2
    end

    test "removes legacy single-file wrappers during split generation", %{tmp_dir: tmp_dir} do
      library = %Library{
        name: :cleanup_demo,
        python_name: "cleanup_demo",
        module_name: CleanupDemo,
        version: "1.0.0"
      }

      legacy_path = Path.join(tmp_dir, "cleanup_demo.ex")

      File.write!(legacy_path, "defmodule CleanupDemo do\nend\n")

      config = %SnakeBridge.Config{
        generated_dir: tmp_dir,
        generated_layout: :split,
        libraries: [library]
      }

      :ok = Generator.generate_library(library, [], [], config)

      refute File.exists?(legacy_path)
      assert File.exists?(Path.join(tmp_dir, "cleanup_demo/__init__.ex"))
    end

    test "generates module files from module docs even without symbols", %{tmp_dir: tmp_dir} do
      library = %Library{
        name: :doc_only,
        python_name: "doc_only",
        module_name: DocOnly,
        version: "1.0.0"
      }

      module_docs = %{
        "doc_only" => %{"docstring" => "Root docs"},
        "doc_only.extra" => %{"docstring" => "Extra docs"}
      }

      config = %SnakeBridge.Config{
        generated_dir: tmp_dir,
        generated_layout: :split,
        libraries: [library]
      }

      :ok = Generator.generate_library(library, [], [], config, module_docs)

      assert File.exists?(Path.join(tmp_dir, "doc_only/__init__.ex"))
      assert File.exists?(Path.join(tmp_dir, "doc_only/extra/__init__.ex"))
    end
  end

  describe "generate_library/4 with single layout" do
    test "creates single file per library (legacy behavior)", %{tmp_dir: tmp_dir} do
      library = %Library{
        name: :numpy,
        python_name: "numpy",
        module_name: Numpy,
        version: "1.26.0"
      }

      functions = [
        %{"name" => "mean", "python_module" => "numpy", "parameters" => []},
        %{"name" => "dot", "python_module" => "numpy.linalg", "parameters" => []}
      ]

      config = %SnakeBridge.Config{
        generated_dir: tmp_dir,
        generated_layout: :single,
        libraries: [library]
      }

      :ok = Generator.generate_library(library, functions, [], config)

      # Single file should exist
      assert File.exists?(Path.join(tmp_dir, "numpy.ex"))
      # Directory structure should NOT exist
      refute File.exists?(Path.join(tmp_dir, "numpy/__init__.ex"))
    end
  end

  # Helper functions

  defp collect_module_definitions(files) do
    Enum.flat_map(files, fn file ->
      content = File.read!(file)

      case Code.string_to_quoted(content, file: file) do
        {:ok, ast} ->
          extract_modules(ast)

        {:error, _} ->
          []
      end
    end)
  end

  defp extract_modules(ast) do
    {_, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          module_name = Enum.join(parts, ".")
          {node, [module_name | acc]}

        node, acc ->
          {node, acc}
      end)

    modules
  end

  defp no_duplicates?(list) do
    length(list) == length(Enum.uniq(list))
  end
end
