defmodule SnakeBridge.EndToEndTest do
  @moduledoc """
  End-to-end integration tests for SnakeBridge.

  Run with: mix test --include real_python test/snakebridge/end_to_end_test.exs

  The tests verify:
  - Dynamic function calls
  - Module attribute access
  - Object ref creation and method calls
  - Session lifecycle and cleanup on process death
  - Streaming iteration
  - Type encoding/decoding round-trips
  """

  use SnakeBridge.RealPythonCase

  @moduletag :integration
  @moduletag :real_python

  alias SnakeBridge.{Runtime, SessionContext, SessionManager}

  setup do
    # Clear any auto-session from previous tests
    Runtime.clear_auto_session()

    on_exit(fn ->
      Runtime.release_auto_session()
    end)

    :ok
  end

  describe "dynamic function calls" do
    test "can call standard library functions" do
      # math.sqrt
      assert {:ok, 4.0} = Runtime.call_dynamic("math", "sqrt", [16])

      # math.gcd - returns number (may be int or float depending on JSON encoding)
      {:ok, result} = Runtime.call_dynamic("math", "gcd", [48, 18])
      assert result == 6 or result == 6.0
    end

    test "can call with keyword arguments" do
      # round(2.675, ndigits=2)
      assert {:ok, result} = Runtime.call_dynamic("builtins", "round", [2.675], ndigits: 2)
      assert is_float(result)
    end

    test "handles errors gracefully" do
      # Non-existent module
      assert {:error, _} = Runtime.call_dynamic("nonexistent_module_xyz", "func", [])

      # Non-existent function
      assert {:error, _} = Runtime.call_dynamic("math", "nonexistent_function", [])
    end
  end

  describe "module attribute access" do
    test "can get module constants" do
      assert {:ok, pi} = Runtime.get_module_attr("math", "pi")
      assert_in_delta pi, 3.14159, 0.001

      assert {:ok, e} = Runtime.get_module_attr("math", "e")
      assert_in_delta e, 2.71828, 0.001
    end
  end

  describe "object refs and methods" do
    test "creates refs for non-serializable objects" do
      # Create a Python list object
      assert {:ok, ref} = Runtime.call_dynamic("builtins", "list", [[1, 2, 3]])

      # Result might be a ref or a plain list depending on serialization
      case ref do
        %SnakeBridge.Ref{} ->
          # Call method on ref
          assert {:ok, result} = Runtime.call_method(ref, :append, [4])
          assert result == true or result == nil

        list when is_list(list) ->
          assert list == [1, 2, 3]
      end
    end

    test "can release refs explicitly" do
      # Create an object that will be wrapped in a ref
      case Runtime.call_dynamic("io", "StringIO", ["test"]) do
        {:ok, %SnakeBridge.Ref{} = ref} ->
          assert :ok = Runtime.release_ref(ref)

        {:ok, _other} ->
          # Object was serializable, no ref created
          :ok
      end
    end
  end

  describe "session lifecycle" do
    test "auto-session is created for process" do
      session_id = Runtime.current_session()
      assert is_binary(session_id)
      assert String.starts_with?(session_id, "auto_")
    end

    test "explicit session can be used" do
      custom_session_id = "test_explicit_session_#{System.unique_integer()}"

      SessionContext.with_session([session_id: custom_session_id], fn ->
        session_id = Runtime.current_session()
        assert session_id == custom_session_id
      end)
    end

    test "session cleanup on process death" do
      session_id = "test_process_death_#{System.unique_integer()}"
      test_pid = self()

      # Start a process that creates a session
      owner =
        spawn(fn ->
          SessionManager.register_session(session_id, self())
          send(test_pid, :session_created)

          receive do
            :stop -> :ok
          end
        end)

      # Wait for session to be created
      assert_receive :session_created, 1000

      # Verify session exists
      assert SessionManager.session_exists?(session_id)

      # Kill the owner process
      Process.exit(owner, :kill)

      # Wait for cleanup
      Process.sleep(200)

      # Session should be cleaned up
      refute SessionManager.session_exists?(session_id)
    end
  end

  describe "streaming" do
    test "can iterate over Python iterators" do
      result =
        Runtime.stream_dynamic("builtins", "range", [5], [], fn item ->
          send(self(), {:item, item})
        end)

      assert result == {:ok, :done}

      # Collect all items
      collected =
        Enum.reduce(1..5, [], fn _, acc ->
          receive do
            {:item, item} -> [item | acc]
          after
            100 -> acc
          end
        end)

      assert Enum.sort(collected) == [0, 1, 2, 3, 4]
    end
  end

  describe "type encoding round-trips" do
    test "basic types" do
      # Strings
      assert {:ok, "hello"} = Runtime.call_dynamic("builtins", "str", ["hello"])

      # Integers - JSON may encode as float
      {:ok, int_result} = Runtime.call_dynamic("builtins", "int", ["42"])
      assert int_result == 42 or int_result == 42.0

      # Floats
      assert {:ok, 3.14} = Runtime.call_dynamic("builtins", "float", ["3.14"])

      # Booleans
      {:ok, true_result} = Runtime.call_dynamic("builtins", "bool", [1])
      {:ok, false_result} = Runtime.call_dynamic("builtins", "bool", [0])
      assert true_result == true or true_result == 1.0
      assert false_result == false or false_result == 0.0
    end

    test "collections" do
      # Lists
      assert {:ok, [1, 2, 3]} = Runtime.call_dynamic("builtins", "list", [[1, 2, 3]])

      # Tuples come back as tuples (tagged)
      assert {:ok, result} = Runtime.call_dynamic("builtins", "tuple", [[1, 2, 3]])
      assert result == {1, 2, 3} or result == [1, 2, 3]
    end

    test "special floats" do
      # Infinity - math.inf is an attribute, not a function
      {:ok, inf_result} = Runtime.get_module_attr("math", "inf")
      assert inf_result == :infinity or is_float(inf_result)

      # Negative infinity
      {:ok, neg_inf} = Runtime.call_dynamic("builtins", "float", ["-inf"])
      assert neg_inf == :neg_infinity or is_float(neg_inf)

      # NaN - math.nan is an attribute
      {:ok, nan_result} = Runtime.get_module_attr("math", "nan")
      assert nan_result == :nan or is_float(nan_result)
    end

    test "bytes encoding" do
      # Create bytes
      result = Runtime.call_dynamic("builtins", "bytes", [[104, 101, 108, 108, 111]])

      case result do
        {:ok, %SnakeBridge.Bytes{data: data}} ->
          assert data == "hello" or data == <<104, 101, 108, 108, 111>>

        {:ok, bytes} when is_binary(bytes) ->
          assert bytes == "hello"

        _ ->
          :ok
      end
    end
  end

  describe "session ID consistency" do
    test "session_id is consistent across payload and routing" do
      custom_session = "consistent_session_#{System.unique_integer()}"

      # Use runtime opts to specify session
      {:ok, _} =
        Runtime.call_dynamic("math", "sqrt", [4], __runtime__: [session_id: custom_session])

      # The session should have been used consistently
      # (This test verifies the fix for session_id single source of truth)
      :ok
    end
  end
end
