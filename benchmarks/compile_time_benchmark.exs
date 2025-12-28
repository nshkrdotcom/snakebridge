# Benchmark: SnakeBridge Compile-Time Operations
#
# Measures performance of scanning, introspection, and code generation.
#
# Run with:
#   mix run benchmarks/compile_time_benchmark.exs
#
# Results are saved to benchmarks/results/compile_TIMESTAMP.json

defmodule SnakeBridge.Benchmarks.CompileTime do
  @moduledoc """
  Benchmarks for SnakeBridge compile-time operations.

  Measures:
  - Module scanning (discovery time per module)
  - Python introspection (extracting signatures, types, docstrings)
  - Code generation (generating Elixir modules)
  - Lock file operations (read, write, verify)
  """

  alias SnakeBridge.Benchmark

  @iterations 5

  def run do
    IO.puts("=" |> String.duplicate(60))
    IO.puts("SnakeBridge Compile-Time Benchmark")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("")

    results = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      elixir_version: System.version(),
      otp_version: System.otp_release(),
      benchmarks: []
    }

    # Benchmark type mapping
    type_mapping_stats = benchmark_type_mapping()
    results = add_benchmark(results, type_mapping_stats)
    Benchmark.print_stats(type_mapping_stats)

    # Benchmark docstring parsing
    docstring_stats = benchmark_docstring_parsing()
    results = add_benchmark(results, docstring_stats)
    Benchmark.print_stats(docstring_stats)

    # Benchmark error translation
    error_stats = benchmark_error_translation()
    results = add_benchmark(results, error_stats)
    Benchmark.print_stats(error_stats)

    # Benchmark lock file operations
    lock_stats = benchmark_lock_operations()
    results = add_benchmark(results, lock_stats)
    Benchmark.print_stats(lock_stats)

    # Benchmark telemetry overhead
    telemetry_stats = benchmark_telemetry_overhead()
    results = add_benchmark(results, telemetry_stats)
    Benchmark.print_stats(telemetry_stats)

    save_results(results)

    IO.puts("")
    IO.puts("Benchmark complete!")
    results
  end

  defp benchmark_type_mapping do
    alias SnakeBridge.Generator.TypeMapper

    # Various Python types to map
    types = [
      %{"type" => "int"},
      %{"type" => "str"},
      %{"type" => "list", "element_type" => %{"type" => "int"}},
      %{"type" => "dict", "key_type" => %{"type" => "str"}, "value_type" => %{"type" => "int"}},
      %{"type" => "optional", "inner_type" => %{"type" => "str"}},
      %{"type" => "union", "types" => [%{"type" => "int"}, %{"type" => "str"}]},
      %{"type" => "numpy.ndarray"},
      %{"type" => "torch.Tensor"}
    ]

    Benchmark.run_iterations(
      "Type Mapping (8 types)",
      fn ->
        Enum.each(types, &TypeMapper.to_spec/1)
      end,
      @iterations
    )
  end

  defp benchmark_docstring_parsing do
    alias SnakeBridge.Docs.RstParser

    # Sample docstrings in different formats
    docstrings = [
      # Google style
      """
      Calculate the mean of values.

      Args:
          values (list[float]): Input values.
          weights (list[float], optional): Weights. Defaults to None.

      Returns:
          float: The weighted mean.

      Raises:
          ValueError: If values is empty.

      Example:
          >>> mean([1, 2, 3])
          2.0
      """,
      # NumPy style
      """
      Compute matrix multiplication.

      Parameters
      ----------
      a : ndarray
          First matrix.
      b : ndarray
          Second matrix.

      Returns
      -------
      ndarray
          Matrix product.

      Examples
      --------
      >>> matmul(a, b)
      array([[1, 2], [3, 4]])
      """
    ]

    Benchmark.run_iterations(
      "Docstring Parsing (2 docs)",
      fn ->
        Enum.each(docstrings, &RstParser.parse/1)
      end,
      @iterations
    )
  end

  defp benchmark_error_translation do
    alias SnakeBridge.ErrorTranslator

    # Sample error messages to translate
    errors = [
      %RuntimeError{message: "mat1 and mat2 shapes cannot be multiplied (3x4 and 5x6)"},
      %RuntimeError{message: "CUDA out of memory. Tried to allocate 8192 MiB"},
      %RuntimeError{message: "expected scalar type Float but found Double"},
      %RuntimeError{message: "Some random error that won't translate"}
    ]

    Benchmark.run_iterations(
      "Error Translation (4 errors)",
      fn ->
        Enum.each(errors, &ErrorTranslator.translate/1)
      end,
      @iterations
    )
  end

  defp benchmark_lock_operations do
    alias SnakeBridge.Lock

    # Create a sample lock structure
    lock = %{
      "snakebridge_version" => "0.5.0",
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "modules" => %{
        "test_module" => %{
          "python_module" => "test",
          "functions" => [
            %{"name" => "func1", "arity" => 2},
            %{"name" => "func2", "arity" => 1}
          ]
        }
      },
      "hardware" => %{
        "accelerator" => "cpu"
      }
    }

    Benchmark.run_iterations(
      "Lock Operations (encode)",
      fn ->
        Jason.encode!(lock)
      end,
      @iterations
    )
  end

  defp benchmark_telemetry_overhead do
    alias SnakeBridge.Telemetry

    Benchmark.run_iterations(
      "Telemetry Event (emit)",
      fn ->
        Telemetry.emit_scan_stop("test_module", :ok, 10, 100)
      end,
      @iterations
    )
  end

  defp add_benchmark(results, stats) do
    benchmark = %{
      name: stats.name,
      iterations: stats.iterations,
      mean_us: stats.mean_us,
      median_us: stats.median_us,
      min_us: stats.min_us,
      max_us: stats.max_us,
      std_dev_us: stats.std_dev_us
    }

    update_in(results.benchmarks, &[benchmark | &1])
  end

  defp save_results(results) do
    File.mkdir_p!("benchmarks/results")

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    filename = "benchmarks/results/compile_#{timestamp}.json"

    json = Jason.encode!(results, pretty: true)
    File.write!(filename, json)

    IO.puts("")
    IO.puts("Results saved to: #{filename}")
  end
end

# Run if executed directly
if System.argv() == [] do
  SnakeBridge.Benchmarks.CompileTime.run()
end
