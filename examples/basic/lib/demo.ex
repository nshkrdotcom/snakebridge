defmodule Demo do
  @moduledoc """
  Basic SnakeBridge Demo - Shows exactly what happens with each Python call.

  Run with: mix run -e Demo.run
  """

  def run do
    Snakepit.run_as_script(fn ->
      IO.puts("""
      ╔═══════════════════════════════════════════════════════════╗
      ║           SnakeBridge Basic Demo - Explicit Calls         ║
      ╚═══════════════════════════════════════════════════════════╝

      This demo shows exactly what happens when Elixir calls Python.
      Each call displays:
        • The Elixir function being invoked
        • The Python module and function being called
        • The arguments being passed
        • The result being returned

      """)

      demo_basic_math()
      demo_string_operations()
      demo_json_operations()
      demo_os_operations()

      IO.puts("""

      ════════════════════════════════════════════════════════════
      Demo complete! Each call above shows the full round-trip:
        Elixir → gRPC → Python → gRPC → Elixir
      ════════════════════════════════════════════════════════════
      """)
    end)
    |> case do
      {:error, reason} ->
        IO.puts("Snakepit script failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end

  defp demo_basic_math do
    IO.puts("─── SECTION 1: Basic Math Operations ───────────────────────")
    IO.puts("")

    # Addition
    python_call("math.pow",
      elixir_module: "Math",
      elixir_function: "pow/2",
      python_module: "math",
      python_function: "pow",
      args: [2, 10],
      description: "Calculate 2^10"
    )

    # Square root
    python_call("math.sqrt",
      elixir_module: "Math",
      elixir_function: "sqrt/1",
      python_module: "math",
      python_function: "sqrt",
      args: [144],
      description: "Calculate √144"
    )

    # Logarithm
    python_call("math.log",
      elixir_module: "Math",
      elixir_function: "log/1",
      python_module: "math",
      python_function: "log",
      args: [2.718281828],
      description: "Calculate ln(e)"
    )

    # Floor
    python_call("math.floor",
      elixir_module: "Math",
      elixir_function: "floor/1",
      python_module: "math",
      python_function: "floor",
      args: [3.7],
      description: "Floor of 3.7"
    )

    # Ceil
    python_call("math.ceil",
      elixir_module: "Math",
      elixir_function: "ceil/1",
      python_module: "math",
      python_function: "ceil",
      args: [3.2],
      description: "Ceiling of 3.2"
    )

    IO.puts("")
  end

  defp demo_string_operations do
    IO.puts("─── SECTION 2: String Operations ───────────────────────────")
    IO.puts("")

    # String length using builtins
    python_call("builtins.len",
      elixir_module: "Builtins",
      elixir_function: "len/1",
      python_module: "builtins",
      python_function: "len",
      args: ["Hello, SnakeBridge!"],
      description: "Get string length"
    )

    # Capitalize words
    python_call("string.capwords",
      elixir_module: "String",
      elixir_function: "capwords/1",
      python_module: "string",
      python_function: "capwords",
      args: ["hello world"],
      description: "Capitalize each word"
    )

    # String type
    python_call("builtins.type",
      elixir_module: "Builtins",
      elixir_function: "type/1",
      python_module: "builtins",
      python_function: "type",
      args: ["test"],
      description: "Get Python type of string"
    )

    IO.puts("")
  end

  defp demo_json_operations do
    IO.puts("─── SECTION 3: JSON Serialization ──────────────────────────")
    IO.puts("")

    data = %{
      "name" => "SnakeBridge",
      "version" => "0.6.0",
      "features" => ["types", "docs", "telemetry"]
    }

    # JSON dumps
    python_call("json.dumps",
      elixir_module: "Json",
      elixir_function: "dumps/1",
      python_module: "json",
      python_function: "dumps",
      args: [data],
      description: "Serialize Elixir map to JSON string"
    )

    json_string = ~s({"greeting": "Hello from Python!", "numbers": [1, 2, 3]})

    # JSON loads
    python_call("json.loads",
      elixir_module: "Json",
      elixir_function: "loads/1",
      python_module: "json",
      python_function: "loads",
      args: [json_string],
      description: "Parse JSON string to Elixir map"
    )

    IO.puts("")
  end

  defp demo_os_operations do
    IO.puts("─── SECTION 4: OS/System Operations ────────────────────────")
    IO.puts("")

    # Get current directory
    python_call("os.getcwd",
      elixir_module: "Os",
      elixir_function: "getcwd/0",
      python_module: "os",
      python_function: "getcwd",
      args: [],
      description: "Get Python's current working directory"
    )

    # Get environment variable
    python_call("os.getenv",
      elixir_module: "Os",
      elixir_function: "getenv/1",
      python_module: "os",
      python_function: "getenv",
      args: ["HOME"],
      description: "Get HOME environment variable"
    )

    # Platform info
    python_call("platform.system",
      elixir_module: "Platform",
      elixir_function: "system/0",
      python_module: "platform",
      python_function: "system",
      args: [],
      description: "Get operating system name"
    )

    python_call("platform.python_version",
      elixir_module: "Platform",
      elixir_function: "python_version/0",
      python_module: "platform",
      python_function: "python_version",
      args: [],
      description: "Get Python version"
    )

    IO.puts("")
  end

  defp python_call(_name, opts) do
    IO.puts("┌─ #{opts[:description]}")
    IO.puts("│")
    IO.puts("│  Elixir call:     #{opts[:elixir_module]}.#{opts[:elixir_function]}")
    IO.puts("│  ────────────────────────────────────────────")
    IO.puts("│  Python module:   #{opts[:python_module]}")
    IO.puts("│  Python function: #{opts[:python_function]}")
    IO.puts("│  Arguments:       #{format_args(opts[:args])}")
    IO.puts("│")

    # Actually make the call via Snakepit with proper payload
    start_time = System.monotonic_time(:microsecond)

    payload = %{
      "library" => opts[:python_module] |> String.split(".") |> List.first(),
      "python_module" => opts[:python_module],
      "function" => opts[:python_function],
      "args" => opts[:args],
      "kwargs" => %{},
      "idempotent" => false
    }

    result =
      case Snakepit.execute("snakebridge.call", payload) do
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end

    elapsed = System.monotonic_time(:microsecond) - start_time

    case result do
      {:ok, value} ->
        IO.puts("│  Response from Python (#{elapsed} us)")
        IO.puts("│")
        IO.puts("└─ Result: {:ok, #{inspect(value, limit: 50, printable_limit: 100)}}")

      {:error, reason} ->
        IO.puts("│  Error from Python (#{elapsed} us)")
        IO.puts("│")
        IO.puts("└─ Result: {:error, #{inspect(reason, limit: 50)}}")
    end

    IO.puts("")
    result
  end

  defp format_args([]), do: "(none)"
  defp format_args(args), do: inspect(args, limit: 50, printable_limit: 100)
end
