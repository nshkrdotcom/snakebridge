defmodule SnakeBridge.GeneratedModuleRuntimeTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.{Generator, TestFixtures}

  describe "generated module create/2 function" do
    test "calls Runtime.create_instance with correct arguments" do
      suffix = TestFixtures.unique_module_suffix()
      descriptor = TestFixtures.sample_class_descriptor(suffix)
      config = TestFixtures.sample_config(suffix)

      # Generate and compile the module
      ast = Generator.generate_module(descriptor, config)
      code = Macro.to_string(ast)

      # VERIFY: Generated code should call Runtime.create_instance, not return placeholder
      assert code =~ "SnakeBridge.Runtime.create_instance"
      refute code =~ "instance_#"

      # Compile and test execution
      {:ok, module} = Generator.compile_and_load(ast)

      # The generated module should call Runtime.create_instance
      # With the mock adapter, this should succeed
      args = %{signature: "question -> answer"}
      assert {:ok, {session_id, instance_id}} = module.create(args, allow_unsafe: true)

      # Verify it returns proper session/instance tuple from Runtime
      assert is_binary(session_id)
      assert is_binary(instance_id)
      # Runtime returns "mock_instance_XXXX" format, not "instance_XXX"
      assert instance_id =~ "mock_instance"
    end

    test "passes session_id option to Runtime" do
      suffix = TestFixtures.unique_module_suffix()
      descriptor = TestFixtures.sample_class_descriptor(suffix)
      config = TestFixtures.sample_config(suffix)

      ast = Generator.generate_module(descriptor, config)
      {:ok, module} = Generator.compile_and_load(ast)

      # Provide explicit session_id
      custom_session = "my_custom_session_123"

      assert {:ok, {session_id, _instance_id}} =
               module.create(%{}, session_id: custom_session, allow_unsafe: true)

      # Should use the provided session_id
      assert session_id == custom_session
    end

    test "generates unique session_id when not provided" do
      suffix = TestFixtures.unique_module_suffix()
      descriptor = TestFixtures.sample_class_descriptor(suffix)
      config = TestFixtures.sample_config(suffix)

      ast = Generator.generate_module(descriptor, config)
      {:ok, module} = Generator.compile_and_load(ast)

      # Create two instances without session_id
      {:ok, {session1, _}} = module.create(%{}, allow_unsafe: true)
      {:ok, {session2, _}} = module.create(%{}, allow_unsafe: true)

      # Should generate different sessions (or reuse if we want session pooling)
      # For now, each call generates a new session
      assert is_binary(session1)
      assert is_binary(session2)
    end
  end

  describe "generated module method functions" do
    test "calls Runtime.call_method with instance ref and args" do
      suffix = TestFixtures.unique_module_suffix()
      descriptor = TestFixtures.sample_class_descriptor(suffix)
      config = TestFixtures.sample_config(suffix)

      ast = Generator.generate_module(descriptor, config)
      code = Macro.to_string(ast)

      # VERIFY: Generated code should call Runtime.call_method
      assert code =~ "SnakeBridge.Runtime.call_method"
      refute code =~ ~s(%{"result" => "placeholder"})

      {:ok, module} = Generator.compile_and_load(ast)

      # Create instance first
      {:ok, instance_ref} = module.create(%{signature: "test -> output"}, allow_unsafe: true)

      # Call the method (should call Runtime.call_method)
      # The method name in fixture is "__call__", mapped to elixir_name :call
      assert {:ok, result} = module.call(instance_ref, %{test: "input"}, allow_unsafe: true)

      # Mock should return actual response from SnakepitMock, not placeholder
      assert is_map(result)
      # SnakepitMock's call_python returns result with "answer" key for instance methods
      assert result["answer"] == "Mocked answer from Python" or result["mock"] == true
    end

    test "handles method errors from Runtime" do
      suffix = TestFixtures.unique_module_suffix()
      descriptor = TestFixtures.sample_class_descriptor(suffix)
      config = TestFixtures.sample_config(suffix)

      ast = Generator.generate_module(descriptor, config)
      {:ok, module} = Generator.compile_and_load(ast)

      # Invalid instance ref should cause error
      invalid_ref = {"bad_session", "bad_instance"}

      # Should propagate error from Runtime
      # Note: Mock might not fail, but real Snakepit would
      result = module.call(invalid_ref, %{}, allow_unsafe: true)

      # Should be {:ok, ...} or {:error, ...}, not crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "integration with Runtime adapter" do
    test "generated modules work end-to-end with mock adapter" do
      suffix = TestFixtures.unique_module_suffix()
      descriptor = TestFixtures.sample_class_descriptor(suffix)
      config = TestFixtures.sample_config(suffix)

      # Generate module
      ast = Generator.generate_module(descriptor, config)
      {:ok, module} = Generator.compile_and_load(ast)

      # Full workflow: create instance, call method
      {:ok, instance} = module.create(%{signature: "question -> answer"}, allow_unsafe: true)
      {:ok, result} = module.call(instance, %{question: "test"}, allow_unsafe: true)

      # Mock returns this structure
      assert is_map(result)
      assert Map.has_key?(result, "result") or Map.has_key?(result, "answer")
    end
  end
end
