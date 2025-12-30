defmodule Demo do
  @moduledoc """
  Comprehensive showcase of SnakeBridge Universal FFI (v0.8.4+).

  The Universal FFI enables calling ANY Python module dynamically,
  without compile-time code generation. This is the "escape hatch"
  for libraries not in your generated wrappers, one-off scripts,
  or runtime-determined module paths.

  ## Key APIs Demonstrated

  - `SnakeBridge.call/4` - Call any Python function
  - `SnakeBridge.get/3` - Get module attributes
  - `SnakeBridge.stream/5` - Stream from generators
  - `SnakeBridge.method/4` - Call methods on refs
  - `SnakeBridge.attr/3` - Get attributes from refs
  - `SnakeBridge.set_attr/4` - Set attributes on refs
  - `SnakeBridge.bytes/1` - Explicit binary encoding
  - `SnakeBridge.ref?/1` - Check if value is a ref
  - `SnakeBridge.current_session/0` - Get current session ID
  - `SnakeBridge.release_auto_session/0` - Clean up session

  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Examples
  alias SnakeBridge.Runtime

  def run do
    Snakepit.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("")
      IO.puts(String.duplicate("=", 60))
      IO.puts("SNAKEBRIDGE UNIVERSAL FFI SHOWCASE")
      IO.puts("Version: 0.8.4+")
      IO.puts(String.duplicate("=", 60))

      demo_basic_calls()
      demo_module_attributes()
      demo_object_methods()
      demo_bytes()
      demo_non_string_keys()
      demo_sessions()
      demo_bang_variants()
      demo_streaming()
      demo_when_to_use()

      IO.puts("")
      IO.puts(String.duplicate("=", 60))
      IO.puts("All demos completed!")
      IO.puts(String.duplicate("=", 60))

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  # ============================================================================
  # 1. Basic Calls
  # ============================================================================

  defp demo_basic_calls do
    section("1. BASIC CALLS")

    IO.puts("No code generation required - works with any installed Python module.")
    IO.puts("")

    # Simple stdlib call
    print_result(
      "SnakeBridge.call(\"math\", \"sqrt\", [16])",
      SnakeBridge.call("math", "sqrt", [16])
    )

    # With keyword arguments
    print_result(
      "SnakeBridge.call(\"builtins\", \"round\", [3.14159], ndigits: 2)",
      SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
    )

    # Submodule paths
    print_result(
      "SnakeBridge.call(\"os.path\", \"join\", [\"/home\", \"user\", \"file.txt\"])",
      SnakeBridge.call("os.path", "join", ["/home", "user", "file.txt"])
    )

    # Atom function names work too
    print_result(
      "SnakeBridge.call(\"builtins\", :str, [\"hello\"])",
      SnakeBridge.call("builtins", :str, ["hello"])
    )
  end

  # ============================================================================
  # 2. Module Attributes
  # ============================================================================

  defp demo_module_attributes do
    section("2. MODULE ATTRIBUTES")

    IO.puts("Getting module-level constants and objects.")
    IO.puts("")

    # Constants
    print_result(
      "SnakeBridge.get(\"math\", \"pi\")",
      SnakeBridge.get("math", "pi")
    )

    print_result(
      "SnakeBridge.get(\"math\", \"e\")",
      SnakeBridge.get("math", "e")
    )

    # System info
    case SnakeBridge.get("sys", "version") do
      {:ok, version} ->
        IO.puts(
          "SnakeBridge.get(\"sys\", \"version\") = {:ok, \"#{String.slice(version, 0..50)}...\"}"
        )

      error ->
        print_result("sys.version", error)
    end

    print_result(
      "SnakeBridge.get(\"os\", \"sep\")",
      SnakeBridge.get("os", "sep")
    )
  end

  # ============================================================================
  # 3. Object Creation and Methods
  # ============================================================================

  defp demo_object_methods do
    section("3. OBJECTS AND METHODS")

    IO.puts("Creating Python objects and calling methods on them.")
    IO.puts("")

    case SnakeBridge.call("pathlib", "Path", ["/tmp/example.txt"]) do
      {:ok, path} ->
        IO.puts("Created: #{inspect(path)}")
        IO.puts("Is ref?: #{SnakeBridge.ref?(path)}")
        IO.puts("")

        # Call methods
        print_result("path.exists()", SnakeBridge.method(path, "exists", []))
        print_result("path.is_absolute()", SnakeBridge.method(path, "is_absolute", []))

        # Get attributes
        print_result("path.name", SnakeBridge.attr(path, "name"))
        print_result("path.suffix", SnakeBridge.attr(path, "suffix"))
        print_result("path.stem", SnakeBridge.attr(path, "stem"))

        # Method chaining via refs
        case SnakeBridge.attr(path, "parent") do
          {:ok, parent} ->
            print_result("path.parent.name", SnakeBridge.attr(parent, "name"))

          error ->
            print_result("path.parent", error)
        end

      error ->
        print_result("Path creation", error)
    end
  end

  # ============================================================================
  # 4. Bytes and Binary Data
  # ============================================================================

  defp demo_bytes do
    section("4. BYTES (Binary Data)")

    IO.puts("Explicit bytes encoding for crypto, protocols, etc.")
    IO.puts("")

    # Hashlib requires bytes, not str
    case SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")]) do
      {:ok, md5_ref} ->
        case SnakeBridge.method(md5_ref, "hexdigest", []) do
          {:ok, hex} ->
            IO.puts("md5(b\"abc\") = #{hex}")
            expected = "900150983cd24fb0d6963f7d28e17f72"
            IO.puts("Expected:   #{expected}")
            IO.puts("Match:      #{hex == expected}")

          error ->
            print_result("hexdigest", error)
        end

      error ->
        print_result("hashlib.md5", error)
    end

    IO.puts("")

    # SHA256
    case SnakeBridge.call("hashlib", "sha256", [SnakeBridge.bytes("secret")]) do
      {:ok, sha_ref} ->
        case SnakeBridge.method(sha_ref, "hexdigest", []) do
          {:ok, sha_hex} ->
            IO.puts("sha256(b\"secret\") = #{String.slice(sha_hex, 0..15)}...")

          error ->
            print_result("sha hexdigest", error)
        end

      error ->
        print_result("hashlib.sha256", error)
    end

    IO.puts("")

    # Base64 encoding
    case SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello world")]) do
      {:ok, encoded} ->
        IO.puts("base64.b64encode(b\"hello world\") = #{inspect(encoded)}")

      error ->
        print_result("b64encode", error)
    end

    IO.puts("")

    # Binary data round-trip
    original = <<0, 1, 2, 127, 128, 255>>

    case SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)]) do
      {:ok, b64} ->
        case SnakeBridge.call("base64", "b64decode", [b64]) do
          {:ok, decoded} ->
            IO.puts("Binary round-trip: #{inspect(original)}")
            IO.puts("Successful:        #{original == decoded}")

          error ->
            print_result("b64decode", error)
        end

      error ->
        print_result("b64encode", error)
    end
  end

  # ============================================================================
  # 5. Non-String Key Maps
  # ============================================================================

  defp demo_non_string_keys do
    section("5. NON-STRING KEY MAPS")

    IO.puts("Maps with integer, tuple, and other non-string keys.")
    IO.puts("")

    # Integer keys
    int_map = %{1 => "one", 2 => "two", 3 => "three"}
    IO.puts("Elixir map: #{inspect(int_map)}")

    case SnakeBridge.call("builtins", "dict", [int_map]) do
      {:ok, returned} when is_map(returned) and not is_struct(returned) ->
        # Dict was returned directly (JSON-serializable)
        value = Map.get(returned, 2)
        IO.puts("Returned map: #{inspect(returned)}")
        IO.puts("map[2] = #{inspect(value)}")
        IO.puts("Keys: #{inspect(Map.keys(returned))}")

      {:ok, ref} when is_struct(ref) ->
        # Returned as ref - call methods on it
        case SnakeBridge.method(ref, "get", [2]) do
          {:ok, value} ->
            IO.puts("dict.get(2) = #{inspect(value)}")

          error ->
            print_result("dict.get", error)
        end

        case SnakeBridge.method(ref, "keys", []) do
          {:ok, keys} ->
            case SnakeBridge.call("builtins", "list", [keys]) do
              {:ok, keys_list} ->
                IO.puts("Keys (list): #{inspect(keys_list)}")

              _ ->
                :ok
            end

          _ ->
            :ok
        end

      error ->
        print_result("dict creation", error)
    end

    IO.puts("")

    # Tuple keys (coordinate maps, etc.)
    coord_map = %{{0, 0} => "origin", {1, 0} => "x-axis", {0, 1} => "y-axis"}
    IO.puts("Coord map: #{inspect(coord_map)}")

    case SnakeBridge.call("builtins", "dict", [coord_map]) do
      {:ok, returned} when is_map(returned) and not is_struct(returned) ->
        # Dict was returned directly
        value = Map.get(returned, {0, 0})
        IO.puts("Returned map: #{inspect(returned)}")
        IO.puts("map[(0,0)] = #{inspect(value)}")

      {:ok, ref} when is_struct(ref) ->
        case SnakeBridge.method(ref, "get", [{0, 0}]) do
          {:ok, origin} ->
            IO.puts("coords[(0,0)] = #{inspect(origin)}")

          error ->
            print_result("coords.get", error)
        end

      error ->
        print_result("coord dict", error)
    end
  end

  # ============================================================================
  # 6. Sessions
  # ============================================================================

  defp demo_sessions do
    section("6. AUTO-SESSIONS")

    IO.puts("Automatic session management.")
    IO.puts("")

    # Clear for clean demo
    Runtime.clear_auto_session()

    # Auto-session is created on first call
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
    session = SnakeBridge.current_session()
    IO.puts("Auto-session: #{session}")
    IO.puts("Starts with 'auto_': #{String.starts_with?(session, "auto_")}")

    # All refs in this process share the session
    {:ok, ref1} = SnakeBridge.call("pathlib", "Path", ["."])
    {:ok, ref2} = SnakeBridge.call("pathlib", "Path", ["/tmp"])

    if SnakeBridge.ref?(ref1) and SnakeBridge.ref?(ref2) do
      IO.puts("ref1.session_id: #{ref1.session_id}")
      IO.puts("ref2.session_id: #{ref2.session_id}")
      IO.puts("Same session: #{ref1.session_id == ref2.session_id}")
    end

    IO.puts("")

    # Process isolation
    # Note: We explicitly release the auto-session before the Task exits
    # to avoid race conditions with SessionManager cleanup
    other_session =
      Task.async(fn ->
        {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
        task_session = SnakeBridge.current_session()
        # Explicitly release before task exits to avoid race with SessionManager
        :ok = SnakeBridge.release_auto_session()
        task_session
      end)
      |> Task.await()

    # Small delay to let any pending cleanup complete
    Process.sleep(50)

    IO.puts("Other process session: #{other_session}")
    IO.puts("Isolated: #{session != other_session}")
  end

  # ============================================================================
  # 7. Bang Variants
  # ============================================================================

  defp demo_bang_variants do
    section("7. BANG VARIANTS")

    IO.puts("Bang (!) variants for raising on error.")
    IO.puts("")

    # call! returns result directly
    result = SnakeBridge.call!("math", "sqrt", [16])
    IO.puts("call!(\"math\", \"sqrt\", [16]) = #{result}")

    # get! for constants
    pi = SnakeBridge.get!("math", "pi")
    IO.puts("get!(\"math\", \"pi\") = #{pi}")

    # method! on refs
    path = SnakeBridge.call!("pathlib", "Path", ["."])
    exists? = SnakeBridge.method!(path, "exists", [])
    IO.puts("method!(path, \"exists\") = #{exists?}")

    # attr! for attributes
    name = SnakeBridge.attr!(path, "name")
    IO.puts("attr!(path, \"name\") = #{name}")

    IO.puts("")

    # Errors raise
    IO.puts("Attempting invalid call (will be caught)...")

    try do
      SnakeBridge.call!("nonexistent_module_xyz", "fn", [])
    rescue
      e ->
        IO.puts("Caught error: #{inspect(e.__struct__)}")
    end
  end

  # ============================================================================
  # 8. Streaming
  # ============================================================================

  defp demo_streaming do
    section("8. STREAMING")

    IO.puts("Streaming from Python generators/iterators.")
    IO.puts("")

    # For streaming, the simplest approach is to convert to a list in Python
    # and return it to Elixir. This avoids the complexity of iterator protocols.
    IO.puts("Creating range and converting to list:")

    case SnakeBridge.call("builtins", "range", [5]) do
      {:ok, range_ref} ->
        case SnakeBridge.call("builtins", "list", [range_ref]) do
          {:ok, items} when is_list(items) ->
            IO.puts("list(range(5)) = #{inspect(items)}")

            # Now iterate in Elixir
            IO.puts("Iterating in Elixir:")

            Enum.each(items, fn item ->
              IO.puts("  Got: #{item}")
            end)

          {:error, reason} ->
            IO.puts("Failed to convert to list: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("Failed to create range: #{inspect(reason)}")
    end

    IO.puts("")

    # Summing example
    IO.puts("Sum of range(10):")

    case SnakeBridge.call("builtins", "range", [10]) do
      {:ok, range_ref} ->
        case SnakeBridge.call("builtins", "list", [range_ref]) do
          {:ok, items} when is_list(items) ->
            total = Enum.sum(items)
            IO.puts("Sum = #{total}")

          {:error, reason} ->
            IO.puts("Failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("Failed: #{inspect(reason)}")
    end

    IO.puts("")

    # Note about true streaming
    IO.puts("Note: For true lazy streaming from Python generators,")
    IO.puts("use SnakeBridge.Runtime.stream_next/2 with StreamRef objects.")
    IO.puts("This is useful for large datasets that don't fit in memory.")
  end

  # ============================================================================
  # 9. When to Use Universal FFI
  # ============================================================================

  defp demo_when_to_use do
    section("9. WHEN TO USE UNIVERSAL FFI")

    IO.puts("""

    USE UNIVERSAL FFI (SnakeBridge.call/4, etc.) when:
    - Calling libraries not in your generated wrappers
    - Module paths are determined at runtime
    - Writing quick scripts or one-off calls
    - Prototyping before adding to libraries config
    - Accessing stdlib modules not worth generating

    USE GENERATED WRAPPERS when:
    - You have a core library you call frequently
    - You want compile-time type hints and docs
    - You want IDE autocomplete
    - You want signature validation at compile time
    - Performance is critical (slightly faster hot path)

    BOTH CAN COEXIST in the same project!

    Example hybrid usage:
    - Generated: NumPy, Pandas (core libraries)
    - Universal: One-off hashlib call, runtime plugins
    """)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp section(title) do
    IO.puts("")
    IO.puts(String.duplicate("=", 60))
    IO.puts(title)
    IO.puts(String.duplicate("=", 60))
    IO.puts("")
  end

  defp print_result(label, {:ok, value}) do
    IO.puts("#{label} = {:ok, #{inspect(value)}}")
  end

  defp print_result(label, {:error, reason}) do
    IO.puts("#{label} = {:error, #{inspect(reason)}}")
    Examples.record_failure()
  end

  defp print_result(label, other) do
    IO.puts("#{label} = #{inspect(other)}")
  end
end
