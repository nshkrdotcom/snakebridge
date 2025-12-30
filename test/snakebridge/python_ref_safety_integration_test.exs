defmodule SnakeBridge.PythonRefSafetyIntegrationTest do
  @moduledoc """
  Integration tests for Python ref safety.

  These tests verify that non-JSON-serializable Python values are properly
  returned as refs, and that JSON-safe values pass through correctly.

  Run with: mix test --include real_python test/snakebridge/python_ref_safety_integration_test.exs
  """
  use ExUnit.Case, async: true

  @moduletag :integration
  @moduletag :real_python

  describe "non-JSON values return refs" do
    test "pathlib.Path returns ref" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert %SnakeBridge.Ref{} = ref
      assert ref.library == "pathlib"
    end

    test "file handle returns ref" do
      {:ok, ref} = SnakeBridge.call("builtins", "open", ["/dev/null", "r"])
      assert %SnakeBridge.Ref{} = ref

      # Clean up
      {:ok, _} = SnakeBridge.method(ref, "close", [])
    end

    test "datetime.datetime object returns ref or decoded value" do
      # datetime.now() returns datetime object which our encoder handles specially
      # but we test that non-JSON objects get wrapped
      {:ok, result} = SnakeBridge.call("datetime", "datetime", [2025, 12, 30])
      # datetime is a tagged type, so it should decode properly
      # This verifies our tagged type handling works
      is_valid = is_map(result) or match?(%SnakeBridge.Ref{}, result)
      assert is_valid
    end
  end

  describe "JSON-safe values pass through" do
    test "int returns int" do
      {:ok, result} = SnakeBridge.call("builtins", "int", ["42"])
      assert result == 42
    end

    test "str returns str" do
      {:ok, result} = SnakeBridge.call("builtins", "str", [42])
      assert result == "42"
    end

    test "float returns float" do
      {:ok, result} = SnakeBridge.call("builtins", "float", ["3.14"])
      assert_in_delta result, 3.14, 0.001
    end

    test "list returns list" do
      {:ok, result} = SnakeBridge.call("builtins", "list", [[1, 2, 3]])
      assert result == [1, 2, 3]
    end

    test "dict with string keys returns map" do
      # Python eval to create a simple dict
      {:ok, result} = SnakeBridge.call("builtins", "dict", [[{"a", 1}, {"b", 2}]])
      assert result == %{"a" => 1, "b" => 2}
    end
  end

  describe "math functions work correctly" do
    test "math.sqrt returns float" do
      {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
      assert result == 4.0
    end

    test "math.gcd returns int" do
      {:ok, result} = SnakeBridge.call("math", "gcd", [48, 18])
      assert result == 6
    end

    test "math.pi returns float" do
      {:ok, result} = SnakeBridge.get("math", "pi")
      assert_in_delta result, 3.14159, 0.0001
    end
  end

  describe "special float handling" do
    test "infinity is handled correctly" do
      {:ok, result} = SnakeBridge.get("math", "inf")
      # Should be decoded back to Elixir infinity or special value
      is_valid = result == :infinity or is_float(result) or is_map(result)
      assert is_valid
    end

    test "nan is handled correctly" do
      {:ok, nan} = SnakeBridge.call("builtins", "float", ["nan"])
      # nan might be decoded to a special value or tagged
      is_valid = nan == :nan or is_map(nan) or is_float(nan)
      assert is_valid
    end
  end

  describe "bytes handling" do
    test "bytes are returned correctly" do
      # hashlib.md5 returns a hash object that needs a ref,
      # but we can test bytes by encoding/decoding
      {:ok, result} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])
      # Result should be bytes, which decode to binary or Bytes struct
      is_valid = is_binary(result) or match?(%SnakeBridge.Bytes{}, result)
      assert is_valid
    end
  end

  describe "complex types" do
    test "tuple is returned correctly" do
      {:ok, result} = SnakeBridge.call("builtins", "tuple", [[1, 2, 3]])
      # Tuple decodes to Elixir tuple
      assert result == {1, 2, 3}
    end

    test "set is returned correctly" do
      {:ok, result} = SnakeBridge.call("builtins", "set", [[1, 2, 3]])
      # Set decodes to Elixir MapSet
      assert MapSet.new([1, 2, 3]) == result
    end

    test "frozenset is returned correctly" do
      {:ok, result} = SnakeBridge.call("builtins", "frozenset", [[1, 2, 3]])
      # Frozenset decodes to Elixir MapSet
      assert MapSet.new([1, 2, 3]) == result
    end
  end

  describe "class instances return refs" do
    test "class instantiation returns ref" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert %SnakeBridge.Ref{} = ref
    end

    test "method on ref returns appropriate type" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, resolved} = SnakeBridge.method(path, "resolve", [])
      # resolve() returns another Path, so it should be a ref
      assert %SnakeBridge.Ref{} = resolved
    end

    test "attribute access on ref works" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
      {:ok, name} = SnakeBridge.attr(path, "name")
      # name is a string
      assert name == "tmp"
    end
  end

  describe "ref operations" do
    test "ref can be used in subsequent calls" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
      {:ok, is_dir} = SnakeBridge.method(path, "is_dir", [])
      assert is_boolean(is_dir)
    end

    test "ref has expected structure" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert is_binary(ref.id)
      assert is_binary(ref.session_id)
      assert ref.library == "pathlib"
      assert ref.python_module == "pathlib"
    end
  end

  describe "error handling" do
    test "import error is properly returned" do
      result = SnakeBridge.call("nonexistent_module_xyz", "foo", [])
      assert {:error, _} = result
    end

    test "attribute error is properly returned" do
      result = SnakeBridge.call("math", "nonexistent_function_xyz", [])
      assert {:error, _} = result
    end

    test "type error is properly returned" do
      result = SnakeBridge.call("math", "sqrt", ["not_a_number"])
      assert {:error, _} = result
    end
  end
end
