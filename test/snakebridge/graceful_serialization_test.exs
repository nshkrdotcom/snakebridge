defmodule SnakeBridge.GracefulSerializationTest do
  @moduledoc """
  Integration tests for graceful serialization behavior.

  These tests verify that containers with non-serializable items preserve
  their structure, with only the non-serializable leaf objects becoming refs.
  This enables access to all serializable fields even when some fields
  contain non-JSON-serializable Python objects.

  Uses REAL Python stdlib objects (re.Pattern) - no mocks.
  """
  use SnakeBridge.RealPythonCase

  @moduletag :integration
  @moduletag :real_python

  describe "graceful serialization preserves container structure" do
    test "validation configs returns list of maps with only pattern as ref" do
      {:ok, configs} =
        SnakeBridge.call_helper("graceful_serialization.validation_configs", [])

      # Result should be a list
      assert is_list(configs)
      assert length(configs) == 3

      # Each entry should be a map with accessible fields
      for entry <- configs do
        assert is_map(entry)

        # Serializable fields should be accessible directly
        assert is_binary(entry["name"])
        assert is_binary(entry["error_message"])
        assert is_boolean(entry["required"])

        # The pattern field should be a ref (re.Pattern is non-serializable)
        pattern = entry["pattern"]
        assert SnakeBridge.ref?(pattern), "pattern should be a ref"
        assert %SnakeBridge.Ref{} = pattern
        assert pattern.type_name == "Pattern"
      end

      # Verify specific values
      first = hd(configs)
      assert first["name"] == "email"
      assert first["error_message"] == "Invalid email format"
      assert first["required"] == true
    end

    test "list with pattern preserves list structure" do
      {:ok, result} = SnakeBridge.call_helper("graceful_serialization.list_with_pattern", [])

      # Result should be a list
      assert is_list(result)
      assert length(result) == 3

      # First and third elements should be integers
      assert result |> Enum.at(0) == 1
      assert result |> Enum.at(2) == 3

      # Middle element should be a ref
      middle = Enum.at(result, 1)
      assert SnakeBridge.ref?(middle)
      assert %SnakeBridge.Ref{} = middle
      assert middle.type_name == "Pattern"
    end

    test "dict with pattern preserves dict structure" do
      {:ok, result} = SnakeBridge.call_helper("graceful_serialization.dict_with_pattern", [])

      # Result should be a map
      assert is_map(result)
      refute SnakeBridge.ref?(result)

      # Serializable fields should be accessible
      assert result["a"] == 1
      assert result["c"] == "hello"

      # "b" should be a ref
      b_value = result["b"]
      assert SnakeBridge.ref?(b_value)
      assert %SnakeBridge.Ref{} = b_value
      assert b_value.type_name == "Pattern"
    end

    test "deeply nested structure preserves all levels" do
      {:ok, result} = SnakeBridge.call_helper("graceful_serialization.nested_structure", [])

      # Navigate the nested structure
      assert is_map(result)
      assert is_map(result["level1"])
      assert is_map(result["level1"]["level2"])
      assert is_list(result["level1"]["level2"]["level3"])

      inner_list = result["level1"]["level2"]["level3"]
      assert length(inner_list) == 4

      # Check values
      assert Enum.at(inner_list, 0) == 1
      assert Enum.at(inner_list, 1) == 2
      assert Enum.at(inner_list, 3) == 4

      # Third element should be a ref
      third = Enum.at(inner_list, 2)
      assert SnakeBridge.ref?(third)
      assert third.type_name == "Pattern"
    end

    test "multiple patterns each become separate refs" do
      {:ok, result} =
        SnakeBridge.call_helper("graceful_serialization.multiple_patterns", [])

      assert is_list(result)
      assert length(result) == 5

      # Check layout: ref, string, ref, int, ref
      assert SnakeBridge.ref?(Enum.at(result, 0))
      assert Enum.at(result, 1) == "separator"
      assert SnakeBridge.ref?(Enum.at(result, 2))
      assert Enum.at(result, 3) == 100
      assert SnakeBridge.ref?(Enum.at(result, 4))

      # Each ref should be distinct
      refs = Enum.filter(result, &SnakeBridge.ref?/1)
      ref_ids = Enum.map(refs, & &1.id)
      assert length(Enum.uniq(ref_ids)) == 3
    end

    test "tuple with pattern preserves tuple semantics" do
      {:ok, result} =
        SnakeBridge.call_helper("graceful_serialization.tuple_with_pattern", [])

      # Tuples are decoded as Elixir tuples
      assert is_tuple(result)
      assert tuple_size(result) == 3

      assert elem(result, 0) == 1
      assert elem(result, 2) == 3

      middle = elem(result, 1)
      assert SnakeBridge.ref?(middle)
      assert middle.type_name == "Pattern"
    end

    test "dict with generator has stream_ref nested" do
      {:ok, result} = SnakeBridge.call_helper("graceful_serialization.dict_with_generator", [])

      # Result should be a map
      assert is_map(result)
      refute SnakeBridge.ref?(result)

      # "status" should be accessible
      assert result["status"] == "ok"

      # "stream" should be a stream ref
      stream = result["stream"]
      assert %SnakeBridge.StreamRef{} = stream
    end

    test "pattern with flags preserves metadata alongside pattern ref" do
      {:ok, result} = SnakeBridge.call_helper("graceful_serialization.pattern_with_flags", [])

      # Result should be a map
      assert is_map(result)
      refute SnakeBridge.ref?(result)

      # Serializable fields should be accessible
      assert result["description"] == "Case-insensitive multiline pattern"
      assert result["test_string"] == "HELLO   WORLD"

      # "pattern" should be a ref
      pattern = result["pattern"]
      assert SnakeBridge.ref?(pattern)
      assert pattern.type_name == "Pattern"
    end
  end

  describe "ref metadata" do
    test "refs include type_name for display" do
      {:ok, result} = SnakeBridge.call_helper("graceful_serialization.list_with_pattern", [])

      ref = Enum.at(result, 1)
      assert ref.type_name == "Pattern"
    end

    test "refs include session_id and id" do
      {:ok, result} = SnakeBridge.call_helper("graceful_serialization.list_with_pattern", [])

      ref = Enum.at(result, 1)
      assert is_binary(ref.id)
      assert is_binary(ref.session_id)
      refute ref.id == ""
      refute ref.session_id == ""
    end
  end

  describe "refs remain usable" do
    test "can access attributes on nested pattern refs" do
      {:ok, configs} =
        SnakeBridge.call_helper("graceful_serialization.validation_configs", [])

      first_pattern = hd(configs)["pattern"]
      assert SnakeBridge.ref?(first_pattern)

      # Access the pattern string via the 'pattern' attribute
      {:ok, pattern_str} = SnakeBridge.attr(first_pattern, "pattern")
      assert is_binary(pattern_str)
      assert String.contains?(pattern_str, "@")
    end

    test "can call match method on pattern refs" do
      {:ok, result} = SnakeBridge.call_helper("graceful_serialization.list_with_pattern", [])

      pattern_ref = Enum.at(result, 1)
      assert SnakeBridge.ref?(pattern_ref)

      # Call the match method - should match digits
      {:ok, match_result} = SnakeBridge.method(pattern_ref, "match", ["12345"])
      # match returns a Match object (ref) or None
      assert SnakeBridge.ref?(match_result) or is_nil(match_result)
    end
  end
end
