defmodule SnakeBridge.Benchmark do
  @moduledoc """
  Benchmark utilities for SnakeBridge performance measurement.

  Provides functions for measuring execution time, collecting statistics,
  and comparing performance across different configurations.

  ## Usage

      # Single measurement
      result = Benchmark.measure("my_operation", fn -> do_work() end)

      # Multiple iterations with statistics
      stats = Benchmark.run_iterations("my_operation", fn -> do_work() end, 10)

      # Compare two runs
      comparison = Benchmark.compare(baseline_stats, current_stats)

  """

  @type measurement :: %{
          name: String.t(),
          time_us: non_neg_integer(),
          value: term(),
          error: String.t() | nil
        }

  @type stats :: %{
          name: String.t(),
          iterations: non_neg_integer(),
          mean_us: float(),
          median_us: float(),
          min_us: non_neg_integer(),
          max_us: non_neg_integer(),
          std_dev_us: float(),
          times_us: [non_neg_integer()]
        }

  @type comparison :: %{
          speedup: float(),
          improvement_percent: float(),
          baseline_mean_us: float(),
          current_mean_us: float()
        }

  @doc """
  Measures the execution time of a single function call.

  Returns a map with:
  - `name` - The benchmark name
  - `time_us` - Execution time in microseconds
  - `value` - The function's return value
  - `error` - Error message if the function raised
  """
  @spec measure(String.t(), (-> term())) :: measurement()
  def measure(name, fun) when is_function(fun, 0) do
    {time_us, value} = :timer.tc(fun)

    %{
      name: name,
      time_us: time_us,
      value: value,
      error: nil
    }
  rescue
    e ->
      %{
        name: name,
        time_us: 0,
        value: nil,
        error: Exception.message(e)
      }
  end

  @doc """
  Runs a function multiple times and collects statistics.

  Returns a map with statistical measures:
  - `mean_us` - Average time in microseconds
  - `median_us` - Median time in microseconds
  - `min_us` - Minimum time
  - `max_us` - Maximum time
  - `std_dev_us` - Standard deviation
  """
  @spec run_iterations(String.t(), (-> term()), non_neg_integer()) :: stats()
  def run_iterations(name, fun, iterations \\ 10) when is_function(fun, 0) do
    # Warmup run
    _ = fun.()

    times =
      Enum.map(1..iterations, fn _ ->
        {time_us, _} = :timer.tc(fun)
        time_us
      end)

    mean = Enum.sum(times) / length(times)
    sorted = Enum.sort(times)
    median = Enum.at(sorted, div(length(sorted), 2))
    min = List.first(sorted)
    max = List.last(sorted)
    std_dev = calculate_std_dev(times, mean)

    %{
      name: name,
      iterations: iterations,
      mean_us: mean,
      median_us: median,
      min_us: min,
      max_us: max,
      std_dev_us: std_dev,
      times_us: times
    }
  end

  @doc """
  Compares two benchmark results and calculates improvement metrics.

  Returns:
  - `speedup` - Ratio (> 1.0 means faster)
  - `improvement_percent` - Percentage improvement (positive is faster)
  """
  @spec compare(map(), map()) :: comparison()
  def compare(%{mean_us: baseline}, %{mean_us: current}) do
    speedup = baseline / current
    improvement = (1 - current / baseline) * 100

    %{
      speedup: Float.round(speedup, 3),
      improvement_percent: Float.round(improvement, 2),
      baseline_mean_us: baseline,
      current_mean_us: current
    }
  end

  @doc """
  Formats a time in microseconds to a human-readable string.

  ## Examples

      iex> Benchmark.format_time(500)
      "500 µs"

      iex> Benchmark.format_time(5_000)
      "5.00 ms"

      iex> Benchmark.format_time(5_000_000)
      "5.00 s"

  """
  @spec format_time(number()) :: String.t()
  def format_time(us) when us < 1_000 do
    "#{round(us)} µs"
  end

  def format_time(us) when us < 1_000_000 do
    "#{Float.round(us / 1_000, 2)} ms"
  end

  def format_time(us) do
    "#{Float.round(us / 1_000_000, 2)} s"
  end

  @doc """
  Formats a byte count to a human-readable string.

  ## Examples

      iex> Benchmark.format_bytes(1024)
      "1.00 KB"

      iex> Benchmark.format_bytes(1_048_576)
      "1.00 MB"

  """
  @spec format_bytes(number()) :: String.t()
  def format_bytes(bytes) when bytes < 1024 do
    "#{round(bytes)} B"
  end

  def format_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 2)} KB"
  end

  def format_bytes(bytes) when bytes < 1024 * 1024 * 1024 do
    "#{Float.round(bytes / (1024 * 1024), 2)} MB"
  end

  def format_bytes(bytes) do
    "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
  end

  @doc """
  Prints a summary of benchmark statistics.
  """
  @spec print_stats(stats()) :: :ok
  def print_stats(stats) do
    IO.puts("")
    IO.puts("#{stats.name}")
    IO.puts(String.duplicate("-", String.length(stats.name)))
    IO.puts("  Iterations: #{stats.iterations}")
    IO.puts("  Mean:       #{format_time(stats.mean_us)}")
    IO.puts("  Median:     #{format_time(stats.median_us)}")
    IO.puts("  Min:        #{format_time(stats.min_us)}")
    IO.puts("  Max:        #{format_time(stats.max_us)}")
    IO.puts("  Std Dev:    #{format_time(stats.std_dev_us)}")
    :ok
  end

  @doc """
  Prints a comparison between two benchmark runs.
  """
  @spec print_comparison(comparison()) :: :ok
  def print_comparison(comparison) do
    IO.puts("")

    status =
      if comparison.improvement_percent >= 0 do
        "FASTER"
      else
        "SLOWER"
      end

    IO.puts("Comparison: #{status}")
    IO.puts("  Speedup: #{comparison.speedup}x")
    IO.puts("  Change:  #{comparison.improvement_percent}%")
    IO.puts("  Baseline: #{format_time(comparison.baseline_mean_us)}")
    IO.puts("  Current:  #{format_time(comparison.current_mean_us)}")
    :ok
  end

  defp calculate_std_dev(times, mean) do
    variance =
      times
      |> Enum.map(fn t -> :math.pow(t - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(times))

    :math.sqrt(variance)
  end
end
