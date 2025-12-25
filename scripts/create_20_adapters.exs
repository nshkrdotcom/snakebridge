# Create adapters for 20 Python libraries and test them
# Run with: mix run scripts/create_20_adapters.exs

Application.ensure_all_started(:snakebridge)

# Mix of stdlib (no install needed) and popular packages (will be installed)
libraries = [
  # Python stdlib - always available
  {"statistics", :stdlib},
  {"json", :stdlib},
  {"base64", :stdlib},
  {"uuid", :stdlib},
  {"hashlib", :stdlib},
  {"math", :stdlib},
  {"random", :stdlib},
  {"string", :stdlib},
  {"re", :stdlib},
  {"textwrap", :stdlib},
  {"difflib", :stdlib},
  {"html", :stdlib},
  {"urllib.parse", :stdlib},
  {"decimal", :stdlib},
  {"fractions", :stdlib},

  # Popular packages - will be installed
  {"chardet", :pip},
  {"numpy", :pip},
  {"sympy", :pip},
  {"requests", :pip},
  {"pyyaml", :pip}
]

IO.puts("=" |> String.duplicate(70))
IO.puts("  Creating adapters for #{length(libraries)} Python libraries")
IO.puts("=" |> String.duplicate(70))

# Install pip packages first
pip_packages =
  libraries |> Enum.filter(fn {_, type} -> type == :pip end) |> Enum.map(&elem(&1, 0))

IO.puts("\nInstalling pip packages: #{Enum.join(pip_packages, ", ")}")

{python, _pip} = SnakeBridge.Python.ensure_environment!(quiet: true)

for pkg <- pip_packages do
  SnakeBridge.Python.ensure_package!(python, pkg, quiet: true)
end

IO.puts("✓ Packages installed\n")

# Create adapters
results =
  Enum.map(libraries, fn {lib, _type} ->
    # Handle module names like urllib.parse -> urllib_parse for file names
    safe_name = String.replace(lib, ".", "_")

    IO.puts("\n>>> Processing: #{lib}")
    IO.puts("-" |> String.duplicate(50))

    # Clean up any existing adapter
    manifest_path = "priv/snakebridge/manifests/#{safe_name}.json"
    example_path = "examples/generated/#{safe_name}"
    bridge_path = "priv/python/bridges/#{safe_name}_bridge.py"

    File.rm(manifest_path)
    File.rm_rf(example_path)
    File.rm(bridge_path)

    # Create the adapter
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        opts = [
          max_functions: 50,
          on_output: fn text -> IO.write(text) end
        ]

        case SnakeBridge.Adapter.Deterministic.create("", lib, opts) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            {:error, reason}
        end
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, reason -> {:error, {:exit, reason}}
      end

    elapsed = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, res} ->
        IO.puts("  ✓ Created in #{elapsed}ms - #{length(res.functions)} functions")
        {:ok, lib, res.functions |> length(), elapsed}

      {:error, reason} ->
        IO.puts("  ✗ Failed: #{inspect(reason)}")
        {:error, lib, reason}
    end
  end)

# Summary
IO.puts("\n")
IO.puts("=" |> String.duplicate(70))
IO.puts("  SUMMARY")
IO.puts("=" |> String.duplicate(70))

{successes, failures} =
  Enum.split_with(results, fn
    {:ok, _, _, _} -> true
    _ -> false
  end)

IO.puts("\nSuccessful: #{length(successes)}/#{length(libraries)}")
IO.puts("")

for {:ok, lib, count, time} <- Enum.sort_by(successes, fn {:ok, _, count, _} -> -count end) do
  IO.puts(
    "  ✓ #{String.pad_trailing(lib, 15)} #{String.pad_leading("#{count}", 3)} functions  (#{time}ms)"
  )
end

if length(failures) > 0 do
  IO.puts("\nFailed: #{length(failures)}")

  for {:error, lib, reason} <- failures do
    IO.puts("  ✗ #{lib}: #{inspect(reason) |> String.slice(0, 50)}")
  end
end

total_funcs = Enum.sum(for {:ok, _, count, _} <- successes, do: count)
IO.puts("\nTotal functions: #{total_funcs}")
IO.puts("Example directories created in: examples/generated/")
