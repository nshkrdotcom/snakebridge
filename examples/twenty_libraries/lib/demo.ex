defmodule Demo do
  @moduledoc """
  Demonstrates calling 20 different Python standard libraries over gRPC.

  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Examples

  @doc """
  Run the complete 20-library demonstration.
  """
  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      print_header()
      results = run_all_libraries()
      print_summary(results)

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp print_header do
    IO.puts("""

    ╔════════════════════════════════════════════════════════════╗
    ║  SnakeBridge: 20 Python Libraries Over gRPC                ║
    ╚════════════════════════════════════════════════════════════╝
    """)
  end

  defp run_all_libraries do
    libraries()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {library_spec, index} ->
      run_library(library_spec, index, length(libraries()))
    end)
  end

  defp libraries do
    [
      {:math, "math",
       [
         {"factorial", [10]},
         {"sqrt", [144]}
       ]},
      {:json, "json",
       [
         {"dumps", [%{"hello" => "world", "count" => 42}]},
         {"loads", ["{\"parsed\": true, \"value\": 123}"]}
       ]},
      {:os, "os",
       [
         {"getcwd", []},
         {"getenv", ["PATH"]}
       ]},
      {:sys, "sys",
       [
         {"getrecursionlimit", []},
         {"getsizeof", [100]}
       ]},
      {:platform, "platform",
       [
         {"system", []},
         {"python_version", []}
       ]},
      {:datetime, "datetime",
       [
         {"datetime", [2024, 12, 25, 10, 30, 0]},
         {"date", [2024, 1, 1]}
       ]},
      {:random, "random",
       [
         {"random", []},
         {"randint", [1, 100]}
       ]},
      {:copy, "copy",
       [
         {"copy", [[1, 2, 3]]},
         {"deepcopy", [%{"nested" => [1, 2, 3]}]}
       ]},
      {:base64, "base64",
       [
         {"b64decode", ["SGVsbG8sIFNuYWtlQnJpZGdlIQ=="]},
         {"b64decode", ["SGVsbG8gV29ybGQh"]}
       ]},
      {:urllib_parse, "urllib.parse",
       [
         {"quote", ["hello world/test"]},
         {"unquote", ["hello%20world%2Ftest"]}
       ]},
      {:re, "re",
       [
         {"match", ["\\d+", "123abc"]},
         {"search", ["[a-z]+", "123abc456"]}
       ]},
      {:collections, "collections",
       [
         {"Counter", [["a", "b", "a", "c", "a", "b"]]},
         {"Counter", [["red", "blue", "red", "green", "blue", "blue"]]}
       ]},
      {:itertools, "itertools",
       [
         {"combinations", [["a", "b", "c"], 2]},
         {"permutations", [["x", "y"], 2]}
       ]},
      {:operator, "operator",
       [
         {"add", [10, 20]},
         {"mul", [5, 7]}
       ]},
      {:string, "string",
       [
         {"capwords", ["hello world from elixir"]},
         {"capwords", ["snakebridge is awesome"]}
       ]},
      {:textwrap, "textwrap",
       [
         {"wrap", ["The quick brown fox jumps over the lazy dog", 20]},
         {"fill", ["SnakeBridge enables seamless Python interop", 25]}
       ]},
      {:uuid, "uuid",
       [
         {"uuid4", []},
         {"uuid4", []}
       ]},
      {:time, "time",
       [
         {"time", []},
         {"ctime", []}
       ]},
      {:calendar, "calendar",
       [
         {"isleap", [2024]},
         {"monthrange", [2024, 2]}
       ]},
      {:statistics, "statistics",
       [
         {"mean", [[10, 20, 30, 40, 50]]},
         {"stdev", [[10, 20, 30, 40, 50]]}
       ]}
    ]
  end

  defp run_library({lib_name, python_module, calls}, index, total) do
    IO.puts("Library #{index}/#{total}: #{lib_name}")

    calls
    |> Enum.map(fn call_spec ->
      result = execute_call(python_module, call_spec)
      print_call_result(call_spec, result)
      result
    end)
  end

  defp execute_call(python_module, {func_name, args}) do
    start_time = System.monotonic_time(:microsecond)
    result = snakepit_call(python_module, func_name, args)
    end_time = System.monotonic_time(:microsecond)
    elapsed_ms = (end_time - start_time) / 1000

    if match?({:error, _}, result) do
      Examples.record_failure()
    end

    %{
      module: python_module,
      function: func_name,
      args: args,
      result: result,
      elapsed_ms: elapsed_ms
    }
  end

  defp print_call_result(call_spec, %{
         function: func,
         args: args,
         result: result,
         elapsed_ms: elapsed_ms
       }) do
    func_display = format_function_name(call_spec, func)
    args_display = format_args(args)
    result_display = format_result(result)
    time_display = format_time(elapsed_ms)

    IO.puts("┌─ #{func_display}")
    IO.puts("│  Arguments: #{args_display}")
    IO.puts("└─ Result: #{result_display}  (#{time_display})")
    IO.puts("")
  end

  defp format_function_name({func_name, _args}, _func), do: "#{func_name}(...)"
  defp format_function_name(_, func), do: func

  defp format_args(args) when is_list(args) do
    inspect(args, limit: 3, pretty: false)
  end

  defp format_args(args), do: inspect(args)

  defp format_result({:ok, value}) do
    value_str = inspect(value, limit: 50, pretty: false)

    truncated =
      if String.length(value_str) > 60,
        do: String.slice(value_str, 0, 57) <> "...",
        else: value_str

    "{:ok, #{truncated}}"
  end

  defp format_result({:error, reason}) do
    "{:error, #{inspect(reason, limit: 3)}}"
  end

  defp format_result(other), do: inspect(other, limit: 3)

  defp format_time(ms) when ms < 1, do: "#{:erlang.float_to_binary(ms * 1000, decimals: 4)} us"
  defp format_time(ms), do: "#{:erlang.float_to_binary(ms / 1, decimals: 4)} ms"

  defp print_summary(results) do
    successful = Enum.filter(results, fn %{result: r} -> match?({:ok, _}, r) end)
    failed = Enum.filter(results, fn %{result: r} -> match?({:error, _}, r) end)

    total_time = Enum.reduce(results, 0, fn %{elapsed_ms: ms}, acc -> acc + ms end)
    avg_time = if length(results) > 0, do: total_time / length(results), else: 0

    {fastest, slowest} = find_extremes(results)

    IO.puts("""
    ════════════════════════════════════════════════════════════
    SUMMARY
    ────────────────────────────────────────────────────────────
    Total libraries called:  #{length(libraries())}
    Total calls made:        #{length(results)}  (#{div(length(results), length(libraries()))} per library)
    Successful calls:        #{length(successful)}
    Failed calls:            #{length(failed)}
    Total time:              #{format_time(total_time)}
    Average per call:        #{format_time(avg_time)}
    Fastest:                 #{format_extreme(fastest)}
    Slowest:                 #{format_extreme(slowest)}
    ════════════════════════════════════════════════════════════
    """)

    if length(failed) > 0 do
      IO.puts("\nFailed calls:")

      Enum.each(failed, fn %{module: m, function: f, result: {:error, reason}} ->
        IO.puts("  - #{m}.#{f}: #{inspect(reason, limit: 2)}")
      end)
    end
  end

  defp find_extremes([]), do: {nil, nil}

  defp find_extremes(results) do
    fastest = Enum.min_by(results, fn %{elapsed_ms: ms} -> ms end)
    slowest = Enum.max_by(results, fn %{elapsed_ms: ms} -> ms end)
    {fastest, slowest}
  end

  defp format_extreme(nil), do: "N/A"

  defp format_extreme(%{module: m, function: f, elapsed_ms: ms}) do
    "#{m}.#{f} (#{format_time(ms)})"
  end

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
