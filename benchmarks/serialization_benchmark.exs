# Benchmark: JSON vs MessagePack serialization for NumPy arrays
#
# This benchmark compares the performance of different serialization
# formats for transferring array data between Python and Elixir.
#
# Run with:
#   mix run benchmarks/serialization_benchmark.exs
#
# Prerequisites:
#   - Snakepit running with NumPy installed
#   - Optional: msgpack-python installed for MessagePack comparison
#
# Results are saved to benchmarks/results/serialization_TIMESTAMP.txt

defmodule SnakeBridge.Benchmarks.Serialization do
  @moduledoc """
  Benchmark scaffold for comparing JSON vs MessagePack serialization.

  Phase 2 planning: Compare serialization overhead for different:
  - Array sizes (1K, 10K, 100K, 1M elements)
  - Array dimensions (1D, 2D, 3D)
  - Data types (float64, float32, int32)
  """

  alias SnakeBridge.Adapters.Numpy

  @array_sizes [
    {1_000, "1K"},
    {10_000, "10K"},
    {100_000, "100K"}
  ]

  @dtypes ["float64", "float32", "int32"]

  def run do
    IO.puts("=" |> String.duplicate(60))
    IO.puts("SnakeBridge Serialization Benchmark")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("")

    # Ensure we're using real adapter
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    results = run_benchmarks()
    print_results(results)
    save_results(results)

    results
  end

  defp run_benchmarks do
    IO.puts("Running benchmarks...")
    IO.puts("")

    for {size, size_label} <- @array_sizes,
        dtype <- @dtypes do
      IO.write("  #{size_label} #{dtype}... ")

      result = benchmark_array_roundtrip(size, dtype)

      IO.puts("done")

      %{
        size: size,
        size_label: size_label,
        dtype: dtype,
        result: result
      }
    end
  end

  defp benchmark_array_roundtrip(size, dtype) do
    iterations = 5

    # Create array data
    data = Enum.to_list(1..size)

    times =
      Enum.map(1..iterations, fn _ ->
        {time_us, result} =
          :timer.tc(fn ->
            Numpy.array(data, dtype: dtype)
          end)

        %{
          time_us: time_us,
          success: match?({:ok, _}, result)
        }
      end)

    successful = Enum.filter(times, & &1.success)

    if length(successful) > 0 do
      avg_time =
        successful
        |> Enum.reduce(0, fn %{time_us: t}, acc -> t + acc end)
        |> Kernel./(length(successful))

      min_time = successful |> Enum.min_by(& &1.time_us) |> Map.fetch!(:time_us)
      max_time = successful |> Enum.max_by(& &1.time_us) |> Map.fetch!(:time_us)

      %{
        avg_time_us: avg_time,
        min_time_us: min_time,
        max_time_us: max_time,
        iterations: length(successful),
        throughput_mb_s: calculate_throughput(size, avg_time, dtype)
      }
    else
      %{error: "All iterations failed"}
    end
  end

  defp calculate_throughput(size, avg_time_us, dtype) do
    bytes_per_element =
      case dtype do
        "float64" -> 8
        "float32" -> 4
        "int64" -> 8
        "int32" -> 4
        _ -> 8
      end

    total_bytes = size * bytes_per_element
    time_seconds = avg_time_us / 1_000_000
    mb_per_second = total_bytes / time_seconds / 1_000_000

    Float.round(mb_per_second, 2)
  end

  defp print_results(results) do
    IO.puts("")
    IO.puts("Results:")
    IO.puts("-" |> String.duplicate(60))
    IO.puts("")

    # Group by dtype
    by_dtype = Enum.group_by(results, & &1.dtype)

    for {dtype, dtype_results} <- by_dtype do
      IO.puts("#{dtype}:")

      for r <- dtype_results do
        case r.result do
          %{avg_time_us: avg, throughput_mb_s: tp} ->
            IO.puts("  #{r.size_label}: #{Float.round(avg / 1000, 2)} ms (#{tp} MB/s)")

          %{error: msg} ->
            IO.puts("  #{r.size_label}: ERROR - #{msg}")
        end
      end

      IO.puts("")
    end
  end

  defp save_results(results) do
    # Ensure results directory exists
    File.mkdir_p!("benchmarks/results")

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    filename = "benchmarks/results/serialization_#{timestamp}.txt"

    content = """
    SnakeBridge Serialization Benchmark Results
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    Configuration:
    - Serialization: JSON (via Jason)
    - Transport: Snakepit gRPC

    Results:
    #{format_results_for_file(results)}

    Notes:
    - Times include Python execution + serialization + transport
    - MessagePack comparison planned for Phase 2
    - Arrow IPC planned for v1.5+ (zero-copy within constraints)
    """

    File.write!(filename, content)
    IO.puts("Results saved to: #{filename}")
  end

  defp format_results_for_file(results) do
    results
    |> Enum.map(fn r ->
      case r.result do
        %{avg_time_us: avg, min_time_us: min, max_time_us: max, throughput_mb_s: tp} ->
          "#{r.size_label} #{r.dtype}: avg=#{Float.round(avg / 1000, 2)}ms min=#{Float.round(min / 1000, 2)}ms max=#{Float.round(max / 1000, 2)}ms throughput=#{tp}MB/s"

        %{error: msg} ->
          "#{r.size_label} #{r.dtype}: ERROR - #{msg}"
      end
    end)
    |> Enum.join("\n")
  end
end

# Run if executed directly
if System.argv() == [] do
  SnakeBridge.Benchmarks.Serialization.run()
end
