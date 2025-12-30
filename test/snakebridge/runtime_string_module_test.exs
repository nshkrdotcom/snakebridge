defmodule SnakeBridge.RuntimeStringModuleTest do
  use ExUnit.Case, async: true

  @moduletag :integration
  @moduletag :real_python

  describe "call/4 with string module path" do
    test "calls Python stdlib module" do
      {:ok, result} = SnakeBridge.Runtime.call("math", "sqrt", [16])
      assert result == 4.0
    end

    test "calls Python stdlib with atom function name" do
      {:ok, result} = SnakeBridge.Runtime.call("math", :sqrt, [16])
      assert result == 4.0
    end

    test "calls submodule with dot notation" do
      {:ok, result} = SnakeBridge.Runtime.call("os.path", "join", ["/tmp", "file.txt"])
      assert result == "/tmp/file.txt"
    end

    test "passes kwargs correctly" do
      # round(2.567, ndigits=2) == 2.57
      {:ok, result} = SnakeBridge.Runtime.call("builtins", "round", [2.567], ndigits: 2)
      assert result == 2.57
    end

    test "returns refs for non-JSON objects" do
      {:ok, ref} = SnakeBridge.Runtime.call("pathlib", "Path", ["."])
      assert %SnakeBridge.Ref{} = ref
    end

    test "returns error for non-existent module" do
      {:error, error} = SnakeBridge.Runtime.call("nonexistent_module_xyz", "fn", [])
      # Accept various error types for import failures
      assert is_map(error) or is_struct(error)
    end

    test "returns error for non-existent function" do
      {:error, error} = SnakeBridge.Runtime.call("math", "nonexistent_fn_xyz", [])
      assert is_map(error) or is_struct(error)
    end
  end

  describe "get_module_attr/3 with string module path" do
    test "gets module constant" do
      {:ok, pi} = SnakeBridge.Runtime.get_module_attr("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end

    test "gets module constant with atom attr name" do
      {:ok, e} = SnakeBridge.Runtime.get_module_attr("math", :e)
      assert_in_delta e, 2.71828, 0.001
    end

    test "gets submodule attribute" do
      {:ok, sep} = SnakeBridge.Runtime.get_module_attr("os", "sep")
      assert is_binary(sep)
    end
  end

  describe "stream/5 with string module path" do
    test "streams generator results" do
      {:ok, :done} =
        SnakeBridge.Runtime.stream(
          "builtins",
          "range",
          [5],
          [],
          fn item ->
            send(self(), {:item, item})
          end
        )

      # Collect results
      items = collect_messages([])
      assert items == [0, 1, 2, 3, 4]
    end

    test "handles single value returns" do
      {:ok, :done} =
        SnakeBridge.Runtime.stream(
          "math",
          "sqrt",
          [16],
          [],
          fn item ->
            send(self(), {:item, item})
          end
        )

      items = collect_messages([])
      assert items == [4.0]
    end

    defp collect_messages(acc) do
      receive do
        {:item, item} -> collect_messages(acc ++ [item])
      after
        100 -> acc
      end
    end
  end

  describe "stream_dynamic/5" do
    test "iterates over Python iterator" do
      {:ok, :done} =
        SnakeBridge.Runtime.stream_dynamic(
          "builtins",
          "iter",
          [[1, 2, 3]],
          [],
          fn item ->
            send(self(), {:item, item})
          end
        )

      items = collect_messages([])
      assert items == [1, 2, 3]
    end
  end
end
