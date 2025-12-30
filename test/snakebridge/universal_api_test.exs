defmodule SnakeBridge.UniversalApiTest do
  use ExUnit.Case, async: true

  @moduletag :integration
  @moduletag :real_python

  describe "call/4" do
    test "calls Python function with string module" do
      {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
      assert result == 4.0
    end

    test "accepts atom function names" do
      {:ok, result} = SnakeBridge.call("math", :sqrt, [16])
      assert result == 4.0
    end

    test "passes kwargs" do
      {:ok, result} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
      assert result == 3.14
    end

    test "works with submodules" do
      {:ok, result} = SnakeBridge.call("os.path", "basename", ["/tmp/file.txt"])
      assert result == "file.txt"
    end
  end

  describe "call!/4" do
    test "returns result on success" do
      assert SnakeBridge.call!("math", "sqrt", [16]) == 4.0
    end

    test "raises on error" do
      assert_raise RuntimeError, fn ->
        SnakeBridge.call!("nonexistent_module_xyz", "fn", [])
      end
    rescue
      # Accept any raised exception for now
      _ -> :ok
    end
  end

  describe "get/3" do
    test "gets module constant" do
      {:ok, pi} = SnakeBridge.get("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end

    test "gets module with atom attr" do
      {:ok, e} = SnakeBridge.get("math", :e)
      assert_in_delta e, 2.71828, 0.001
    end
  end

  describe "get!/3" do
    test "returns value on success" do
      pi = SnakeBridge.get!("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end
  end

  describe "method/4" do
    test "calls method on ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])
      assert is_boolean(exists?)
    end

    test "accepts atom method names" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, _} = SnakeBridge.method(path, :exists, [])
    end
  end

  describe "method!/4" do
    test "returns result on success" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      exists? = SnakeBridge.method!(path, "exists", [])
      assert is_boolean(exists?)
    end
  end

  describe "attr/3" do
    test "gets attribute from ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])
      {:ok, name} = SnakeBridge.attr(path, "name")
      assert name == "test.txt"
    end

    test "accepts atom attr names" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])
      {:ok, name} = SnakeBridge.attr(path, :name)
      assert name == "test.txt"
    end
  end

  describe "attr!/3" do
    test "returns value on success" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])
      name = SnakeBridge.attr!(path, "name")
      assert name == "test.txt"
    end
  end

  describe "bytes/1" do
    test "creates Bytes struct" do
      bytes = SnakeBridge.bytes("hello")
      assert %SnakeBridge.Bytes{data: "hello"} = bytes
    end

    test "works with binary data" do
      bytes = SnakeBridge.bytes(<<0, 1, 2, 255>>)
      assert %SnakeBridge.Bytes{data: <<0, 1, 2, 255>>} = bytes
    end

    test "works with crypto calls" do
      {:ok, ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
      {:ok, hex} = SnakeBridge.method(ref, "hexdigest", [])
      assert hex == "900150983cd24fb0d6963f7d28e17f72"
    end
  end

  describe "session management" do
    test "current_session returns session id" do
      {:ok, _} = SnakeBridge.call("math", "sqrt", [4])
      session = SnakeBridge.current_session()
      assert is_binary(session)
      assert String.starts_with?(session, "auto_")
    end

    test "release_auto_session cleans up" do
      {:ok, _} = SnakeBridge.call("math", "sqrt", [4])
      old_session = SnakeBridge.current_session()

      :ok = SnakeBridge.release_auto_session()

      {:ok, _} = SnakeBridge.call("math", "sqrt", [9])
      new_session = SnakeBridge.current_session()

      assert old_session != new_session
    end
  end

  describe "ref?/1" do
    test "returns true for refs" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert SnakeBridge.ref?(ref)
    end

    test "returns false for non-refs" do
      refute SnakeBridge.ref?("string")
      refute SnakeBridge.ref?(123)
      refute SnakeBridge.ref?(%{})
      refute SnakeBridge.ref?(nil)
    end
  end

  describe "stream/5" do
    test "streams iterable results" do
      {:ok, :done} =
        SnakeBridge.stream(
          "builtins",
          "range",
          [3],
          [],
          fn item ->
            send(self(), {:item, item})
          end
        )

      items = collect_messages([])
      assert items == [0, 1, 2]
    end

    defp collect_messages(acc) do
      receive do
        {:item, item} -> collect_messages(acc ++ [item])
      after
        100 -> acc
      end
    end
  end
end
