# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Statistics
# Run with: mix run examples/generated/statistics/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Statistics Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# correlation [○ stateless]
# Pearson's correlation coefficient
IO.puts("Testing correlation...")

try do
  result = SnakeBridge.Statistics.correlation(%{x: [1, 2, 3], y: [1, 2, 3]})
  IO.puts("  ✓ correlation: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ correlation: #{Exception.message(e)}")
end

# covariance [○ stateless]
# Covariance
IO.puts("Testing covariance...")

try do
  result = SnakeBridge.Statistics.covariance(%{x: [1, 2, 3], y: [1, 2, 3]})
  IO.puts("  ✓ covariance: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ covariance: #{Exception.message(e)}")
end

# fmean [○ stateless]
# Convert data to floats and compute the arithmetic mean.
IO.puts("Testing fmean...")

try do
  result = SnakeBridge.Statistics.fmean(%{data: [1, 2, 3]})
  IO.puts("  ✓ fmean: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ fmean: #{Exception.message(e)}")
end

# geometric_mean [○ stateless]
# Convert data to floats and compute the geometric mean.
IO.puts("Testing geometric_mean...")

try do
  result = SnakeBridge.Statistics.geometric_mean(%{data: [1, 2, 3]})
  IO.puts("  ✓ geometric_mean: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ geometric_mean: #{Exception.message(e)}")
end

# harmonic_mean [○ stateless]
# Return the harmonic mean of data.
IO.puts("Testing harmonic_mean...")

try do
  result = SnakeBridge.Statistics.harmonic_mean(%{data: [1, 2, 3]})
  IO.puts("  ✓ harmonic_mean: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ harmonic_mean: #{Exception.message(e)}")
end

# linear_regression [○ stateless]
# Slope and intercept for simple linear regression.
IO.puts("Testing linear_regression...")

try do
  result = SnakeBridge.Statistics.linear_regression(%{x: [1, 2, 3], y: [1, 2, 3]})
  IO.puts("  ✓ linear_regression: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ linear_regression: #{Exception.message(e)}")
end

# mean [○ stateless]
# Return the sample arithmetic mean of data.
IO.puts("Testing mean...")

try do
  result = SnakeBridge.Statistics.mean(%{data: [1, 2, 3]})
  IO.puts("  ✓ mean: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ mean: #{Exception.message(e)}")
end

# median [○ stateless]
# Return the median (middle value) of numeric data.
IO.puts("Testing median...")

try do
  result = SnakeBridge.Statistics.median(%{data: [1, 2, 3]})
  IO.puts("  ✓ median: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ median: #{Exception.message(e)}")
end

# median_grouped [○ stateless]
# Estimates the median for numeric data binned around the midpoints
IO.puts("Testing median_grouped...")

try do
  result = SnakeBridge.Statistics.median_grouped(%{data: [1, 2, 3]})
  IO.puts("  ✓ median_grouped: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ median_grouped: #{Exception.message(e)}")
end

# median_high [○ stateless]
# Return the high median of data.
IO.puts("Testing median_high...")

try do
  result = SnakeBridge.Statistics.median_high(%{data: [1, 2, 3]})
  IO.puts("  ✓ median_high: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ median_high: #{Exception.message(e)}")
end

# median_low [○ stateless]
# Return the low median of numeric data.
IO.puts("Testing median_low...")

try do
  result = SnakeBridge.Statistics.median_low(%{data: [1, 2, 3]})
  IO.puts("  ✓ median_low: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ median_low: #{Exception.message(e)}")
end

# mode [○ stateless]
# Return the most common data point from discrete or nominal data.
IO.puts("Testing mode...")

try do
  result = SnakeBridge.Statistics.mode(%{data: [1, 2, 3]})
  IO.puts("  ✓ mode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ mode: #{Exception.message(e)}")
end

# multimode [○ stateless]
# Return a list of the most frequently occurring values.
IO.puts("Testing multimode...")

try do
  result = SnakeBridge.Statistics.multimode(%{data: [1, 2, 3]})
  IO.puts("  ✓ multimode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ multimode: #{Exception.message(e)}")
end

# namedtuple [○ stateless]
# Returns a new subclass of tuple with named fields.
IO.puts("Testing namedtuple...")

try do
  result = SnakeBridge.Statistics.namedtuple(%{typename: "test", field_names: "test"})
  IO.puts("  ✓ namedtuple: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ namedtuple: #{Exception.message(e)}")
end

# pstdev [○ stateless]
# Return the square root of the population variance.
IO.puts("Testing pstdev...")

try do
  result = SnakeBridge.Statistics.pstdev(%{data: [1, 2, 3]})
  IO.puts("  ✓ pstdev: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ pstdev: #{Exception.message(e)}")
end

# quantiles [○ stateless]
# Divide *data* into *n* continuous intervals with equal probability.
IO.puts("Testing quantiles...")

try do
  result = SnakeBridge.Statistics.quantiles(%{data: [1, 2, 3]})
  IO.puts("  ✓ quantiles: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ quantiles: #{Exception.message(e)}")
end

# stdev [○ stateless]
# Return the square root of the sample variance.
IO.puts("Testing stdev...")

try do
  result = SnakeBridge.Statistics.stdev(%{data: [1, 2, 3]})
  IO.puts("  ✓ stdev: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ stdev: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
