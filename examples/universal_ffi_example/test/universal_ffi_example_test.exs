defmodule UniversalFfiExampleTest do
  use ExUnit.Case

  setup do
    # Ensure clean session state for each test
    SnakeBridge.Runtime.clear_auto_session()
    :ok
  end

  describe "SnakeBridge.call/4" do
    test "calls function with string module" do
      assert {:ok, 4.0} = SnakeBridge.call("math", "sqrt", [16])
    end

    test "accepts kwargs" do
      assert {:ok, 3.14} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
    end

    test "works with submodules" do
      assert {:ok, "/tmp/file"} = SnakeBridge.call("os.path", "join", ["/tmp", "file"])
    end

    test "returns ref for objects" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert SnakeBridge.ref?(ref)
    end
  end

  describe "SnakeBridge.get/3" do
    test "gets module constant" do
      {:ok, pi} = SnakeBridge.get("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end

    test "accepts atom attr name" do
      {:ok, e} = SnakeBridge.get("math", :e)
      assert_in_delta e, 2.71828, 0.001
    end
  end

  describe "SnakeBridge.method/4" do
    test "calls method on ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])
      assert is_boolean(exists?)
    end

    test "accepts atom method name" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, is_abs?} = SnakeBridge.method(path, :is_absolute, [])
      assert is_boolean(is_abs?)
    end
  end

  describe "SnakeBridge.attr/3" do
    test "gets attribute from ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])
      assert {:ok, "test.txt"} = SnakeBridge.attr(path, "name")
    end

    test "accepts atom attr name" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.py"])
      assert {:ok, ".py"} = SnakeBridge.attr(path, :suffix)
    end
  end

  describe "SnakeBridge.bytes/1" do
    test "enables hashlib calls" do
      {:ok, ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
      {:ok, hex} = SnakeBridge.method(ref, "hexdigest", [])
      assert hex == "900150983cd24fb0d6963f7d28e17f72"
    end

    test "binary data round-trips correctly" do
      original = <<0, 1, 2, 128, 255>>
      {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)])
      {:ok, decoded} = SnakeBridge.call("base64", "b64decode", [encoded])
      assert decoded == original
    end
  end

  describe "non-string key maps" do
    test "integer keys work" do
      {:ok, ref} = SnakeBridge.call("builtins", "dict", [%{1 => "one", 2 => "two"}])
      {:ok, value} = SnakeBridge.method(ref, "get", [1])
      assert value == "one"
    end

    test "tuple keys work" do
      {:ok, ref} = SnakeBridge.call("builtins", "dict", [%{{0, 0} => "origin"}])
      {:ok, value} = SnakeBridge.method(ref, "get", [{0, 0}])
      assert value == "origin"
    end
  end

  describe "sessions" do
    test "auto-session created on first call" do
      SnakeBridge.Runtime.clear_auto_session()
      {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
      session = SnakeBridge.current_session()
      assert String.starts_with?(session, "auto_")
    end

    test "session reused for subsequent calls" do
      SnakeBridge.Runtime.clear_auto_session()
      {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
      s1 = SnakeBridge.current_session()
      {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
      s2 = SnakeBridge.current_session()
      assert s1 == s2
    end

    test "release creates new session" do
      SnakeBridge.Runtime.clear_auto_session()
      {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
      old = SnakeBridge.current_session()
      SnakeBridge.release_auto_session()
      {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
      new = SnakeBridge.current_session()
      assert old != new
    end
  end

  describe "bang variants" do
    test "call! returns result" do
      assert SnakeBridge.call!("math", "sqrt", [16]) == 4.0
    end

    test "get! returns result" do
      pi = SnakeBridge.get!("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end

    test "method! returns result" do
      path = SnakeBridge.call!("pathlib", "Path", ["."])
      exists? = SnakeBridge.method!(path, "exists", [])
      assert is_boolean(exists?)
    end

    test "attr! returns result" do
      path = SnakeBridge.call!("pathlib", "Path", ["/tmp/test.txt"])
      assert SnakeBridge.attr!(path, "name") == "test.txt"
    end

    test "call! raises on error" do
      assert_raise RuntimeError, fn ->
        SnakeBridge.call!("nonexistent_xyz", "fn", [])
      end
    end
  end

  describe "ref?/1" do
    test "identifies refs" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert SnakeBridge.ref?(ref)
    end

    test "rejects non-refs" do
      refute SnakeBridge.ref?("string")
      refute SnakeBridge.ref?(42)
      refute SnakeBridge.ref?(%{})
    end
  end

  describe "streaming" do
    test "streams from iterator" do
      items = []
      {:ok, pid} = Agent.start_link(fn -> [] end)

      SnakeBridge.stream("builtins", "range", [5], [], fn item ->
        Agent.update(pid, &[item | &1])
      end)

      result = Agent.get(pid, & &1) |> Enum.reverse()
      Agent.stop(pid)
      assert result == [0, 1, 2, 3, 4]
    end
  end
end
