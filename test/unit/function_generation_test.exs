defmodule SnakeBridge.FunctionGenerationTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.{Generator, TestFixtures}

  describe "generate_function_module/2" do
    test "generates module for Python functions" do
      # Test fixture with functions, not classes
      descriptor = %{
        name: "JsonFunctions",
        python_path: "json",
        docstring: "Python's built-in JSON encoder/decoder",
        functions: [
          %{name: "dumps", elixir_name: :dumps, python_path: "json.dumps"},
          %{name: "loads", elixir_name: :loads, python_path: "json.loads"}
        ]
      }

      config = TestFixtures.sample_config()
      ast = Generator.generate_function_module(descriptor, config)
      code = Macro.to_string(ast)

      # Verify module structure
      assert code =~ "defmodule"
      assert code =~ "def dumps("
      assert code =~ "def loads("
    end

    test "function modules call Runtime.call_function not create_instance" do
      descriptor = %{
        name: "JsonFunctions",
        python_path: "json",
        functions: [
          %{name: "dumps", elixir_name: :dumps, python_path: "json.dumps"}
        ]
      }

      config = TestFixtures.sample_config()
      ast = Generator.generate_function_module(descriptor, config)
      code = Macro.to_string(ast)

      # Should call Runtime.call_function, NOT create_instance
      assert code =~ "SnakeBridge.Runtime.call_function"
      refute code =~ "create_instance"
    end

    test "function modules do not have create/2 function" do
      descriptor = %{
        name: "JsonFunctions",
        python_path: "json",
        functions: [
          %{name: "dumps", elixir_name: :dumps, python_path: "json.dumps"}
        ]
      }

      config = TestFixtures.sample_config()
      ast = Generator.generate_function_module(descriptor, config)
      code = Macro.to_string(ast)

      # Functions are stateless, no instance creation
      refute code =~ "def create("
      refute code =~ "@type t ::"
    end

    test "generates function specs with proper types" do
      descriptor = %{
        name: "JsonFunctions",
        python_path: "json",
        functions: [
          %{name: "dumps", elixir_name: :dumps, python_path: "json.dumps"}
        ]
      }

      config = TestFixtures.sample_config()
      ast = Generator.generate_function_module(descriptor, config)
      code = Macro.to_string(ast)

      # Functions should have specs
      assert code =~ "@spec dumps"
      assert code =~ "{:ok, term()} | {:error, term()}"
    end

    test "includes module documentation for function modules" do
      descriptor = %{
        name: "JsonFunctions",
        python_path: "json",
        docstring: "Python's built-in JSON encoder/decoder",
        functions: [
          %{name: "dumps", elixir_name: :dumps, python_path: "json.dumps"}
        ]
      }

      config = TestFixtures.sample_config()
      ast = Generator.generate_function_module(descriptor, config)
      code = Macro.to_string(ast)

      assert code =~ "@moduledoc"
      assert code =~ "Python's built-in JSON encoder/decoder"
    end
  end

  describe "generate_all/1 with functions" do
    test "generates both class and function modules" do
      config = %{
        TestFixtures.sample_config()
        | classes: [
            %{
              python_path: "dspy.Predict",
              elixir_module: TestApp.Predict,
              constructor: %{args: %{}, session_aware: true},
              methods: [%{name: "__call__", elixir_name: :call, streaming: false}]
            }
          ],
          functions: [
            %{
              name: "configure",
              python_path: "dspy.configure",
              elixir_name: :configure,
              elixir_module: DspyFunctions
            }
          ]
      }

      {:ok, modules} = Generator.generate_all(config)

      # Should have both class and function modules
      assert length(modules) == 2
    end

    test "handles config with only functions (no classes)" do
      config = %{
        TestFixtures.sample_config()
        | classes: [],
          functions: [
            %{
              name: "dumps",
              python_path: "json.dumps",
              elixir_name: :dumps,
              elixir_module: Json
            }
          ]
      }

      {:ok, modules} = Generator.generate_all(config)

      # Should generate function module even with no classes
      assert length(modules) == 1
    end

    test "handles config with only classes (no functions)" do
      config = %{
        TestFixtures.sample_config()
        | classes: [
            %{
              python_path: "dspy.Predict",
              elixir_module: TestApp.Predict,
              constructor: %{args: %{}, session_aware: true},
              methods: [%{name: "__call__", elixir_name: :call, streaming: false}]
            }
          ],
          functions: []
      }

      {:ok, modules} = Generator.generate_all(config)

      # Should work with just classes (backwards compatible)
      assert length(modules) == 1
    end
  end
end
