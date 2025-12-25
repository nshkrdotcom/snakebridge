# Test all generated examples (simplified)
# Run with: mix run scripts/test_all_examples.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(2000)

IO.puts("=" |> String.duplicate(70))
IO.puts("  Testing All Generated Examples")
IO.puts("=" |> String.duplicate(70))
IO.puts("")

# Find all example directories
example_dirs =
  Path.wildcard("examples/generated/*/stateless_examples.exs")
  |> Enum.map(&Path.dirname/1)
  |> Enum.sort()

IO.puts("Found #{length(example_dirs)} adapters to test\n")

results =
  Enum.map(example_dirs, fn dir ->
    lib_name = Path.basename(dir)

    example_file = Path.join(dir, "stateless_examples.exs")

    if File.exists?(example_file) do
      content = File.read!(example_file)

      # Find all function calls
      function_calls =
        Regex.scan(~r/result = (SnakeBridge\.[^\n]+)/, content)
        |> Enum.map(fn [_, call] -> String.trim(call) end)

      if length(function_calls) > 0 do
        test_results =
          Enum.map(function_calls, fn call ->
            func_name =
              case Regex.run(~r/\.(\w+)\(%/, call) do
                [_, name] -> name
                _ -> "unknown"
              end

            result =
              try do
                {result, _} = Code.eval_string(call)

                case result do
                  {:ok, _} -> :ok
                  {:error, _} -> :error
                  _ -> :ok
                end
              rescue
                _ -> :error
              catch
                _, _ -> :error
              end

            {func_name, result}
          end)

        successes = Enum.filter(test_results, fn {_, r} -> r == :ok end)
        failures = Enum.filter(test_results, fn {_, r} -> r == :error end)

        IO.puts("#{lib_name}:")
        for {name, _} <- successes, do: IO.puts("  ✓ #{name}")
        for {name, _} <- failures, do: IO.puts("  ✗ #{name}")

        {lib_name, length(successes), length(test_results)}
      else
        IO.puts("#{lib_name}: (no functions)")
        {lib_name, 0, 0}
      end
    else
      IO.puts("#{lib_name}: (no file)")
      {lib_name, 0, 0}
    end
  end)

IO.puts("\n")
IO.puts("=" |> String.duplicate(70))
IO.puts("  RESULTS")
IO.puts("=" |> String.duplicate(70))

for {lib, success, total} <-
      Enum.sort_by(results, fn {_, s, t} -> if t > 0, do: -s / t, else: 0 end) do
  if total > 0 do
    pct = Float.round(success / total * 100, 0) |> trunc()
    status = if success == total, do: "✓", else: "○"
    IO.puts("  #{status} #{String.pad_trailing(lib, 15)} #{success}/#{total} (#{pct}%)")
  end
end

total_s = Enum.sum(for {_, s, _} <- results, do: s)
total_t = Enum.sum(for {_, _, t} <- results, do: t)

IO.puts("")

IO.puts(
  "Total: #{total_s}/#{total_t} functions working (#{trunc(total_s / max(total_t, 1) * 100)}%)"
)
