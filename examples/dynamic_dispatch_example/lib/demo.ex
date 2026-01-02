defmodule Demo do
  @moduledoc """
  Demonstrates dynamic dispatch (Universal FFI) patterns in SnakeBridge.

  Shows BOTH the lower-level APIs AND the new convenience APIs:
  - `Runtime.call_dynamic/4` vs `SnakeBridge.call/4`
  - `Dynamic.call/4` vs `SnakeBridge.method/4`
  - `Dynamic.get_attr/3` vs `SnakeBridge.attr/3`

  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Dynamic
  alias SnakeBridge.Examples
  alias SnakeBridge.Runtime

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Dynamic Dispatch Example - Universal FFI Showcase")
      IO.puts(String.duplicate("=", 50))

      # Original APIs (v0.7.3+)
      section("ORIGINAL API (v0.7.3+)")
      demo_runtime_call_dynamic()
      demo_dynamic_call()

      # New Universal FFI Convenience APIs (v0.8.4+)
      section("NEW CONVENIENCE API (v0.8.4+)")
      demo_snakebridge_call()
      demo_snakebridge_get()
      demo_snakebridge_method_attr()
      demo_ref_check()

      # Comparison
      section("API COMPARISON")
      demo_api_comparison()

      # Error handling
      section("ERROR HANDLING")
      demo_invalid_ref_error()

      IO.puts("")
      IO.puts(String.duplicate("=", 50))
      IO.puts("All demos completed!")

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  # ============================================================================
  # Original API (v0.7.3+) - Still valid and useful for advanced cases
  # ============================================================================

  defp demo_runtime_call_dynamic do
    step("Runtime.call_dynamic/4 - lower-level API")

    # Direct Python function call
    print_result("math.sqrt(144)", Runtime.call_dynamic("math", "sqrt", [144]))

    # Create object
    case Runtime.call_dynamic("pathlib", "Path", ["."]) do
      {:ok, ref} ->
        IO.puts("Created Path ref: #{inspect(ref)}")
        :ok

      error ->
        print_result("pathlib.Path", error)
    end
  end

  defp demo_dynamic_call do
    step("Dynamic.call/4 for method dispatch")

    case Runtime.call_dynamic("pathlib", "Path", ["."]) do
      {:ok, ref} ->
        print_result("path.exists()", Dynamic.call(ref, :exists, []))

      other ->
        print_result("Path creation", other)
    end
  end

  # ============================================================================
  # New Universal FFI Convenience API (v0.8.4+)
  # ============================================================================

  defp demo_snakebridge_call do
    step("SnakeBridge.call/4 - the RECOMMENDED way")

    # Simple function call
    print_result(
      "SnakeBridge.call(\"math\", \"sqrt\", [16])",
      SnakeBridge.call("math", "sqrt", [16])
    )

    # With kwargs
    print_result(
      "SnakeBridge.call(\"builtins\", \"round\", [3.14159], ndigits: 2)",
      SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
    )

    # Submodule call
    print_result(
      "SnakeBridge.call(\"os.path\", \"join\", [\"/tmp\", \"file.txt\"])",
      SnakeBridge.call("os.path", "join", ["/tmp", "file.txt"])
    )

    # Create object - returns ref
    case SnakeBridge.call("pathlib", "Path", ["."]) do
      {:ok, ref} ->
        IO.puts("Created Path via call/4: #{inspect(ref)}")
        :ok

      error ->
        print_result("Path creation", error)
    end

    # Bang variant
    result = SnakeBridge.call!("math", "sqrt", [25])
    IO.puts("call!(\"math\", \"sqrt\", [25]) = #{result}")
  end

  defp demo_snakebridge_get do
    step("SnakeBridge.get/3 for module attributes")

    # Get module constant
    print_result(
      "SnakeBridge.get(\"math\", \"pi\")",
      SnakeBridge.get("math", "pi")
    )

    # Atom attr name also works
    print_result(
      "SnakeBridge.get(\"math\", :e)",
      SnakeBridge.get("math", :e)
    )

    # Bang variant
    sep = SnakeBridge.get!("os", "sep")
    IO.puts("get!(\"os\", \"sep\") = #{inspect(sep)}")
  end

  defp demo_snakebridge_method_attr do
    step("SnakeBridge.method/4, attr/3 for refs")

    case SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"]) do
      {:ok, path} ->
        # Call method
        print_result("path.exists()", SnakeBridge.method(path, "exists", []))

        # Get attribute
        print_result("path.name", SnakeBridge.attr(path, "name"))
        print_result("path.suffix", SnakeBridge.attr(path, :suffix))

        # Bang variant
        stem = SnakeBridge.attr!(path, "stem")
        IO.puts("attr!(path, \"stem\") = #{stem}")

      error ->
        print_result("Path creation", error)
    end
  end

  defp demo_ref_check do
    step("SnakeBridge.ref?/1 to identify refs")

    {:ok, path_ref} = SnakeBridge.call("pathlib", "Path", ["."])
    {:ok, number} = SnakeBridge.call("math", "sqrt", [16])

    IO.puts("ref?(path_ref) = #{SnakeBridge.ref?(path_ref)}")
    IO.puts("ref?(4.0) = #{SnakeBridge.ref?(number)}")
    IO.puts("ref?(\"string\") = #{SnakeBridge.ref?("string")}")
  end

  # ============================================================================
  # Comparison: Old API vs New API
  # ============================================================================

  defp demo_api_comparison do
    step("Side-by-side comparison")

    # OLD: Runtime.call_dynamic/4
    {:ok, r1} = Runtime.call_dynamic("math", "sqrt", [16])

    # NEW: SnakeBridge.call/4
    {:ok, r2} = SnakeBridge.call("math", "sqrt", [16])

    IO.puts("Runtime.call_dynamic result: #{r1}")
    IO.puts("SnakeBridge.call result:     #{r2}")
    IO.puts("Both equal: #{r1 == r2}")

    IO.puts("")

    # OLD: Dynamic.call/4
    {:ok, path} = Runtime.call_dynamic("pathlib", "Path", ["."])
    {:ok, e1} = Dynamic.call(path, :exists, [])

    # NEW: SnakeBridge.method/4
    {:ok, path2} = SnakeBridge.call("pathlib", "Path", ["."])
    {:ok, e2} = SnakeBridge.method(path2, :exists, [])

    IO.puts("Dynamic.call result:     #{e1}")
    IO.puts("SnakeBridge.method result: #{e2}")
  end

  # ============================================================================
  # Error handling
  # ============================================================================

  defp demo_invalid_ref_error do
    step("Invalid ref error handling")

    try do
      Dynamic.call(%{"id" => "bad"}, :noop, [])
      IO.puts("Result: expected invalid ref error")
      Examples.record_failure()
    rescue
      exception in ArgumentError ->
        IO.puts("Caught expected error: #{Exception.message(exception)}")
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp section(title) do
    IO.puts("")
    IO.puts(String.duplicate("-", 50))
    IO.puts(title)
    IO.puts(String.duplicate("-", 50))
  end

  defp step(title) do
    IO.puts("")
    IO.puts("== #{title} ==")
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
