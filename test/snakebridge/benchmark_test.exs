defmodule SnakeBridge.BenchmarkTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Benchmark

  describe "measure/2" do
    test "measures execution time of a function" do
      result = Benchmark.measure("test", fn -> :timer.sleep(10) end)

      assert result.name == "test"
      assert result.time_us >= 10_000
      assert result.time_us < 100_000
    end

    test "returns the function result" do
      result = Benchmark.measure("add", fn -> 1 + 1 end)

      assert result.value == 2
    end

    test "handles errors gracefully" do
      result = Benchmark.measure("error", fn -> raise "test error" end)

      assert result.error =~ "test error"
    end
  end

  describe "run_iterations/3" do
    test "runs multiple iterations and collects stats" do
      stats = Benchmark.run_iterations("test", fn -> :timer.sleep(1) end, 3)

      assert stats.iterations == 3
      assert stats.mean_us > 0
      assert stats.min_us > 0
      assert stats.max_us >= stats.min_us
      assert stats.std_dev_us >= 0
    end

    test "calculates median correctly" do
      # Use consistent timing with some work
      stats = Benchmark.run_iterations("test", fn -> :timer.sleep(1) end, 5)

      assert stats.median_us >= 0
    end
  end

  describe "format_time/1" do
    test "formats microseconds" do
      assert Benchmark.format_time(500) == "500 µs"
    end

    test "formats milliseconds" do
      result = Benchmark.format_time(5_000)
      assert result =~ "5.0 ms" or result =~ "5.00 ms"
    end

    test "formats seconds" do
      result = Benchmark.format_time(5_000_000)
      assert result =~ "5.0 s" or result =~ "5.00 s"
    end
  end

  describe "format_bytes/1" do
    test "formats bytes" do
      assert Benchmark.format_bytes(500) == "500 B"
    end

    test "formats kilobytes" do
      assert Benchmark.format_bytes(5_000) == "4.88 KB"
    end

    test "formats megabytes" do
      assert Benchmark.format_bytes(5_000_000) == "4.77 MB"
    end

    test "formats gigabytes" do
      assert Benchmark.format_bytes(5_000_000_000) == "4.66 GB"
    end
  end

  describe "compare/2" do
    test "compares two benchmark results" do
      baseline = %{mean_us: 1000}
      current = %{mean_us: 800}

      comparison = Benchmark.compare(baseline, current)

      assert comparison.speedup > 1.0
      assert comparison.improvement_percent > 0
    end

    test "handles regression" do
      baseline = %{mean_us: 1000}
      current = %{mean_us: 1200}

      comparison = Benchmark.compare(baseline, current)

      assert comparison.speedup < 1.0
      assert comparison.improvement_percent < 0
    end
  end
end
