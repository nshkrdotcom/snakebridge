defmodule SnakeBridge.GeneratorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator
  alias SnakeBridge.TestFixtures

  describe "generate_module/2" do
    test "generates module AST from class descriptor" do
      descriptor = TestFixtures.sample_class_descriptor()
      config = TestFixtures.sample_config()

      ast = Generator.generate_module(descriptor, config)

      assert {:defmodule, _, _} = ast
    end

    test "generates constructor function" do
      descriptor = TestFixtures.sample_class_descriptor()
      config = TestFixtures.sample_config()

      ast = Generator.generate_module(descriptor, config)
      code = Macro.to_string(ast)

      assert String.contains?(code, "def create(")
      assert String.contains?(code, "@spec create")
    end

    test "generates method wrappers" do
      descriptor = TestFixtures.sample_class_descriptor()
      config = TestFixtures.sample_config()

      ast = Generator.generate_module(descriptor, config)
      code = Macro.to_string(ast)

      assert String.contains?(code, "def __call__(")
      # Or transformed name if specified in config
    end

    test "includes module documentation" do
      descriptor = TestFixtures.sample_class_descriptor()
      config = TestFixtures.sample_config()

      ast = Generator.generate_module(descriptor, config)
      code = Macro.to_string(ast)

      assert String.contains?(code, "@moduledoc")
      assert String.contains?(code, descriptor.docstring)
    end

    test "generates typespecs from Python types" do
      descriptor = TestFixtures.sample_class_descriptor()
      config = TestFixtures.sample_config()

      ast = Generator.generate_module(descriptor, config)
      code = Macro.to_string(ast)

      assert String.contains?(code, "@spec")
      assert String.contains?(code, "@type t ::")
    end
  end

  describe "optimization passes" do
    test "inlines constants when possible" do
      descriptor = %{
        TestFixtures.sample_class_descriptor()
        | constant_fields: ["DEFAULT_TEMPERATURE"]
      }

      config = TestFixtures.sample_config()

      ast = Generator.generate_module(descriptor, config)
      optimized = Generator.optimize(ast)

      # Constants should be module attributes
      code = Macro.to_string(optimized)
      assert String.contains?(code, "@default_temperature")
    end

    test "removes unused imports" do
      ast =
        quote do
          defmodule Test do
            import Unused.Module

            def used_function, do: :ok
          end
        end

      optimized = Generator.optimize(ast)
      code = Macro.to_string(optimized)

      refute String.contains?(code, "import Unused.Module")
    end
  end

  describe "compile_time vs runtime generation" do
    test "generates compile-time code when configured" do
      descriptor = TestFixtures.sample_class_descriptor()
      config = %{TestFixtures.sample_config() | compilation_mode: :compile_time}

      ast = Generator.generate_module(descriptor, config)

      # Should use @before_compile
      code = Macro.to_string(ast)
      assert String.contains?(code, "@before_compile")
    end

    test "generates runtime loader when configured" do
      descriptor = TestFixtures.sample_class_descriptor()
      config = %{TestFixtures.sample_config() | compilation_mode: :runtime}

      ast = Generator.generate_module(descriptor, config)

      # Should use @on_load
      code = Macro.to_string(ast)
      assert String.contains?(code, "@on_load")
    end
  end
end
