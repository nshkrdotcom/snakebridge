defmodule Demo do
  @moduledoc """
  SnakeBridge Error Translation Demo - Shows how ML errors get translated.

  Run with: mix run -e Demo.run

  This demo showcases SnakeBridge's error translation capabilities:
    1. Shape mismatch errors (tensor operations)
    2. Out of memory errors (GPU/CPU memory exhaustion)
    3. Dtype mismatch errors (type conflicts)
    4. How ErrorTranslator converts raw errors to structured errors
    5. Actionable suggestions for fixing common ML issues
  """

  alias SnakeBridge.ErrorTranslator
  alias SnakeBridge.Error.{ShapeMismatchError, OutOfMemoryError, DtypeMismatchError}
  alias SnakeBridge.Examples

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("""
      ====================================================================
      ||           SnakeBridge ML Error Translation Demo                ||
      ====================================================================

      This demo shows how SnakeBridge translates cryptic Python/ML errors
      into structured, actionable error messages with helpful suggestions.

      """)

      demo_shape_mismatch_errors()
      demo_out_of_memory_errors()
      demo_dtype_mismatch_errors()
      demo_error_translator_directly()
      demo_real_python_errors()

      IO.puts("""

      ====================================================================
      Demo complete! Key takeaways:

        1. ShapeMismatch errors include shape info and fix suggestions
        2. OutOfMemory errors show memory stats and recovery strategies
        3. DtypeMismatch errors suggest conversion methods
        4. ErrorTranslator.translate/1 handles raw Python exceptions
        5. All errors provide actionable guidance for developers
      ====================================================================
      """)

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  # ===========================================================================
  # Section 1: Shape Mismatch Errors
  # ===========================================================================

  defp demo_shape_mismatch_errors do
    IO.puts("--- SECTION 1: Shape Mismatch Errors --------------------------")
    IO.puts("")

    # Scenario 1.1: Matrix multiplication shape mismatch
    show_error_scenario("Matrix Multiplication Shape Mismatch",
      description: "Simulating PyTorch matmul with incompatible shapes",
      elixir_call: "Tensor.matmul/2",
      python_module: "torch",
      python_function: "matmul",
      args: ["tensor[3x4]", "tensor[5x6]"],
      raw_error: "RuntimeError: shapes cannot be multiplied (3x4 and 5x6)",
      translated: fn ->
        ShapeMismatchError.new(:matmul,
          shape_a: [3, 4],
          shape_b: [5, 6],
          message: "shapes cannot be multiplied (3x4 and 5x6)"
        )
      end
    )

    # Scenario 1.2: Broadcasting shape mismatch
    show_error_scenario("Broadcasting Shape Mismatch",
      description: "Simulating NumPy broadcasting failure",
      elixir_call: "Tensor.add/2",
      python_module: "numpy",
      python_function: "add",
      args: ["array[10, 3]", "array[10, 5]"],
      raw_error: "RuntimeError: broadcasting cannot match shapes [10, 3] vs [10, 5]",
      translated: fn ->
        ShapeMismatchError.new(:broadcast,
          shape_a: [10, 3],
          shape_b: [10, 5],
          message: "broadcasting cannot match shapes"
        )
      end
    )

    # Scenario 1.3: Dimension mismatch in elementwise op
    show_error_scenario("Elementwise Operation Dimension Mismatch",
      description: "Simulating elementwise multiply with different sizes",
      elixir_call: "Tensor.multiply/2",
      python_module: "torch",
      python_function: "mul",
      args: ["tensor[100]", "tensor[200]"],
      raw_error: "RuntimeError: size of tensor a (100) must match the size of tensor b (200)",
      translated: fn ->
        ShapeMismatchError.new(:elementwise,
          shape_a: [100],
          shape_b: [200],
          message: "size of tensor a (100) must match the size of tensor b (200)"
        )
      end
    )

    IO.puts("")
  end

  # ===========================================================================
  # Section 2: Out of Memory Errors
  # ===========================================================================

  defp demo_out_of_memory_errors do
    IO.puts("--- SECTION 2: Out of Memory Errors ---------------------------")
    IO.puts("")

    # Scenario 2.1: CUDA out of memory
    show_error_scenario("CUDA Out of Memory",
      description: "Simulating GPU memory exhaustion during training",
      elixir_call: "Model.forward/2",
      python_module: "torch.nn",
      python_function: "forward",
      args: ["model", "large_batch[1024, 3, 224, 224]"],
      raw_error:
        "RuntimeError: CUDA out of memory. Tried to allocate 8192 MiB (GPU 0; 16384 MiB total; 2048 MiB free)",
      translated: fn ->
        OutOfMemoryError.new({:cuda, 0},
          requested_mb: 8192,
          available_mb: 2048,
          total_mb: 16384,
          message: "CUDA out of memory"
        )
      end
    )

    # Scenario 2.2: Apple MPS out of memory
    show_error_scenario("Apple MPS Out of Memory",
      description: "Simulating Metal Performance Shaders memory limit",
      elixir_call: "Model.train_step/2",
      python_module: "torch",
      python_function: "backward",
      args: ["loss", "model"],
      raw_error: "RuntimeError: MPS backend out of memory",
      translated: fn ->
        OutOfMemoryError.new(:mps,
          message: "MPS backend out of memory"
        )
      end
    )

    # Scenario 2.3: CPU memory exhaustion
    show_error_scenario("CPU Memory Exhaustion",
      description: "Simulating system memory limit during data loading",
      elixir_call: "DataLoader.load_batch/1",
      python_module: "torch.utils.data",
      python_function: "DataLoader.__next__",
      args: ["dataloader"],
      raw_error: "RuntimeError: out of memory trying to allocate 32768 MB",
      translated: fn ->
        OutOfMemoryError.new(:cpu,
          requested_mb: 32768,
          message: "out of memory trying to allocate 32768 MB"
        )
      end
    )

    IO.puts("")
  end

  # ===========================================================================
  # Section 3: Dtype Mismatch Errors
  # ===========================================================================

  defp demo_dtype_mismatch_errors do
    IO.puts("--- SECTION 3: Dtype Mismatch Errors --------------------------")
    IO.puts("")

    # Scenario 3.1: Float vs Double
    show_error_scenario("Float32 vs Float64 Mismatch",
      description: "Simulating dtype conflict in tensor operation",
      elixir_call: "Tensor.matmul/2",
      python_module: "torch",
      python_function: "matmul",
      args: ["tensor[float32]", "tensor[float64]"],
      raw_error: "RuntimeError: expected scalar type Float but found Double",
      translated: fn ->
        DtypeMismatchError.new(:float32, :float64,
          operation: :matmul,
          message: "expected scalar type Float but found Double"
        )
      end
    )

    # Scenario 3.2: Float vs Integer
    show_error_scenario("Float vs Integer Mismatch",
      description: "Simulating operation between float and int tensors",
      elixir_call: "Tensor.divide/2",
      python_module: "torch",
      python_function: "div",
      args: ["tensor[float32]", "tensor[int64]"],
      raw_error: "RuntimeError: expected dtype torch.float32 but got torch.int64",
      translated: fn ->
        DtypeMismatchError.new(:float32, :int64,
          operation: :divide,
          message: "expected dtype torch.float32 but got torch.int64"
        )
      end
    )

    # Scenario 3.3: Half precision mismatch
    show_error_scenario("Half Precision Mismatch",
      description: "Simulating mixed precision training error",
      elixir_call: "Model.forward/2",
      python_module: "torch.nn",
      python_function: "Linear.forward",
      args: ["input[float16]", "weights[float32]"],
      raw_error: "RuntimeError: expected scalar type Half but found Float",
      translated: fn ->
        DtypeMismatchError.new(:float16, :float32,
          operation: :linear,
          message: "expected scalar type Half but found Float"
        )
      end
    )

    IO.puts("")
  end

  # ===========================================================================
  # Section 4: ErrorTranslator Direct Usage
  # ===========================================================================

  defp demo_error_translator_directly do
    IO.puts("--- SECTION 4: ErrorTranslator Direct Usage -------------------")
    IO.puts("")

    IO.puts("The ErrorTranslator module provides utilities for translating")
    IO.puts("raw Python errors into structured SnakeBridge errors.")
    IO.puts("")

    # Demo translate/1 with RuntimeError
    IO.puts("4.1 Translating a RuntimeError:")
    IO.puts("----")
    raw_error = %RuntimeError{message: "shapes cannot be multiplied (64x128 and 256x512)"}
    IO.puts("    Input:  #{inspect(raw_error)}")
    translated = ErrorTranslator.translate(raw_error)
    IO.puts("    Output: #{inspect(translated, pretty: true, width: 60)}")
    IO.puts("")
    IO.puts("    Formatted message:")
    IO.puts("    " <> String.replace(Exception.message(translated), "\n", "\n    "))
    IO.puts("")

    # Demo translate_message/1
    IO.puts("4.2 Translating error message strings:")
    IO.puts("----")

    messages = [
      "CUDA out of memory. Tried to allocate 4096 MiB",
      "expected scalar type Float but found Long",
      "size of tensor a (50) must match the size of tensor b (100)"
    ]

    for msg <- messages do
      IO.puts("    Message: \"#{msg}\"")

      case ErrorTranslator.translate_message(msg) do
        nil ->
          IO.puts("    Result:  (no translation)")

        error ->
          IO.puts("    Result:  #{inspect(error.__struct__)}")
      end

      IO.puts("")
    end

    # Demo dtype_from_string/1
    IO.puts("4.3 Converting dtype strings:")
    IO.puts("----")
    dtypes = ["Float", "Double", "torch.float32", "torch.int64", "Half"]

    for dtype <- dtypes do
      atom = ErrorTranslator.dtype_from_string(dtype)
      IO.puts("    \"#{dtype}\" -> #{inspect(atom)}")
    end

    IO.puts("")
  end

  # ===========================================================================
  # Section 5: Real Python Error Translation
  # ===========================================================================

  defp demo_real_python_errors do
    IO.puts("--- SECTION 5: Real Python Error Scenarios --------------------")
    IO.puts("")

    IO.puts("Demonstrating actual Python calls that produce errors,")
    IO.puts("showing how try/rescue with ErrorTranslator works.")
    IO.puts("")

    # Real Python call that causes a division by zero
    python_call_with_error("Division by Zero",
      description: "Calling Python division with zero denominator",
      python_module: "operator",
      python_function: "truediv",
      args: [1, 0]
    )

    # Real Python call that causes a type error
    python_call_with_error("Type Error",
      description: "Passing incompatible types to Python",
      python_module: "operator",
      python_function: "add",
      args: ["string", 42]
    )

    # Real Python call that causes attribute error
    python_call_with_error("Attribute Error",
      description: "Accessing non-existent attribute",
      python_module: "builtins",
      python_function: "getattr",
      args: ["hello", "nonexistent_method"]
    )

    # Real Python call - successful to show contrast
    python_call_with_error("Successful Call (Contrast)",
      description: "A working Python call for comparison",
      python_module: "math",
      python_function: "sqrt",
      args: [16],
      expect_error: false
    )

    IO.puts("")
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp show_error_scenario(title, opts) do
    _description = opts[:description]
    elixir_call = opts[:elixir_call]
    python_module = opts[:python_module]
    python_function = opts[:python_function]
    args = opts[:args]
    raw_error = opts[:raw_error]
    translated_fn = opts[:translated]

    IO.puts("+-----------------------------------------------------------------")
    IO.puts("| #{title}")
    IO.puts("+-----------------------------------------------------------------")
    IO.puts("|")
    IO.puts("|  Elixir call:     #{elixir_call}")
    IO.puts("|  --------------------------------------------")
    IO.puts("|  Python module:   #{python_module}")
    IO.puts("|  Python function: #{python_function}")
    IO.puts("|  Arguments:       #{inspect(args)}")
    IO.puts("|")
    IO.puts("|  Raw Python Error:")
    IO.puts("|    #{raw_error}")
    IO.puts("|")

    # Show the translation process
    translated_error = translated_fn.()

    IO.puts("|  SnakeBridge Translation:")
    IO.puts("|    Error Type: #{inspect(translated_error.__struct__)}")
    IO.puts("|")
    IO.puts("|  Structured Error Fields:")
    print_error_fields(translated_error)
    IO.puts("|")
    IO.puts("|  Formatted Error Message:")
    formatted = Exception.message(translated_error)

    for line <- String.split(formatted, "\n") do
      IO.puts("|    #{line}")
    end

    IO.puts("|")
    IO.puts("+-----------------------------------------------------------------")
    IO.puts("")
  end

  defp print_error_fields(%ShapeMismatchError{} = error) do
    IO.puts("|    operation:  #{inspect(error.operation)}")
    IO.puts("|    shape_a:    #{inspect(error.shape_a)}")
    IO.puts("|    shape_b:    #{inspect(error.shape_b)}")
    IO.puts("|    suggestion: #{error.suggestion}")
  end

  defp print_error_fields(%OutOfMemoryError{} = error) do
    IO.puts("|    device:       #{inspect(error.device)}")
    IO.puts("|    requested_mb: #{inspect(error.requested_mb)}")
    IO.puts("|    available_mb: #{inspect(error.available_mb)}")
    IO.puts("|    total_mb:     #{inspect(error.total_mb)}")
    IO.puts("|    suggestions:  #{length(error.suggestions)} custom + defaults")
  end

  defp print_error_fields(%DtypeMismatchError{} = error) do
    IO.puts("|    expected:   #{inspect(error.expected)}")
    IO.puts("|    got:        #{inspect(error.got)}")
    IO.puts("|    operation:  #{inspect(error.operation)}")
    IO.puts("|    suggestion: #{error.suggestion}")
  end

  defp print_error_fields(_error) do
    IO.puts("|    (unknown error type)")
  end

  defp python_call_with_error(title, opts) do
    description = opts[:description]
    python_module = opts[:python_module]
    python_function = opts[:python_function]
    args = opts[:args]
    expect_error = Keyword.get(opts, :expect_error, true)

    IO.puts("+-----------------------------------------------------------------")
    IO.puts("| #{title}")
    IO.puts("+-----------------------------------------------------------------")
    IO.puts("|")
    IO.puts("|  #{description}")
    IO.puts("|  --------------------------------------------")
    IO.puts("|  Python module:   #{python_module}")
    IO.puts("|  Python function: #{python_function}")
    IO.puts("|  Arguments:       #{inspect(args)}")
    IO.puts("|")

    start_time = System.monotonic_time(:microsecond)

    result =
      try do
        case snakepit_call(python_module, python_function, args) do
          {:ok, value} ->
            {:ok, value}

          {:error, %{message: message} = error} ->
            # Try to translate the error
            translated = ErrorTranslator.translate(%RuntimeError{message: message})

            if translated == %RuntimeError{message: message} do
              {:error, error}
            else
              {:translated, translated}
            end

          {:error, reason} when is_binary(reason) ->
            translated = ErrorTranslator.translate(%RuntimeError{message: reason})

            if translated == %RuntimeError{message: reason} do
              {:error, reason}
            else
              {:translated, translated}
            end

          {:error, reason} ->
            {:error, reason}

          other ->
            {:ok, other}
        end
      rescue
        e ->
          translated = ErrorTranslator.translate(e)

          if translated == e do
            {:rescue, e}
          else
            {:translated, translated}
          end
      end

    elapsed = System.monotonic_time(:microsecond) - start_time

    record_expectation(expect_error, result)

    case result do
      {:ok, value} ->
        IO.puts("|  Response from Python (#{elapsed} us)")
        IO.puts("|")
        IO.puts("|  Result: {:ok, #{inspect(value, limit: 50)}}")

      {:error, reason} ->
        IO.puts("|  Error from Python (#{elapsed} us)")
        IO.puts("|")
        error_type = if is_struct(reason), do: inspect(reason.__struct__), else: "unknown"
        IO.puts("|  Error Type: #{error_type}")
        IO.puts("|  Message: #{get_error_message(reason)}")
        IO.puts("|")
        IO.puts("|  (Standard Python error - no ML-specific translation needed)")

      {:translated, translated_error} ->
        IO.puts("|  Error from Python (#{elapsed} us)")
        IO.puts("|")
        IO.puts("|  Translated Error Type: #{inspect(translated_error.__struct__)}")
        IO.puts("|")
        IO.puts("|  Formatted Error:")
        formatted = Exception.message(translated_error)

        for line <- String.split(formatted, "\n") do
          IO.puts("|    #{line}")
        end

      {:rescue, exception} ->
        IO.puts("|  Exception raised (#{elapsed} us)")
        IO.puts("|")
        IO.puts("|  Exception: #{inspect(exception)}")
        IO.puts("|  Message: #{Exception.message(exception)}")
    end

    IO.puts("|")
    IO.puts("+-----------------------------------------------------------------")
    IO.puts("")
  end

  defp get_error_message(%{message: message}), do: message
  defp get_error_message(other), do: inspect(other, limit: 50)

  defp record_expectation(true, {:ok, _value}), do: Examples.record_failure()
  defp record_expectation(true, {:translated, _error}), do: :ok
  defp record_expectation(true, {:error, _reason}), do: :ok
  defp record_expectation(true, {:rescue, _exception}), do: Examples.record_failure()
  defp record_expectation(true, _other), do: Examples.record_failure()

  defp record_expectation(false, {:ok, _value}), do: :ok
  defp record_expectation(false, _other), do: Examples.record_failure()

  # Helper to call Python via Snakepit with proper payload format
  defp snakepit_call(python_module, python_function, args) do
    payload =
      SnakeBridge.Runtime.protocol_payload()
      |> Map.merge(%{
        "library" => python_module |> String.split(".") |> List.first(),
        "python_module" => python_module,
        "function" => python_function,
        "args" => args,
        "kwargs" => %{},
        "idempotent" => false
      })

    case Snakepit.execute("snakebridge.call", payload) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      other -> {:ok, other}
    end
  end
end
