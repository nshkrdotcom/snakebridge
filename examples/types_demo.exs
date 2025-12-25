#!/usr/bin/env elixir

# SnakeBridge Types Demo
#
# This script demonstrates the type encoding/decoding system that enables
# lossless data exchange between Elixir and Python.
#
# Usage:
#   elixir examples/types_demo.exs

Mix.install([
  {:snakebridge, path: Path.expand("..", __DIR__)},
  {:jason, "~> 1.4"}
])

alias SnakeBridge.Types.{Encoder, Decoder}

defmodule TypesDemo do
  def run do
    IO.puts("=== SnakeBridge Types Demo ===\n")

    demonstrate_primitives()
    demonstrate_special_floats()
    demonstrate_tuples()
    demonstrate_sets()
    demonstrate_datetime()
    demonstrate_nested_structures()
    demonstrate_round_trip()

    IO.puts("\n✓ All type demonstrations complete!")
  end

  defp demonstrate_primitives do
    IO.puts("--- Primitives ---")

    examples = [
      nil,
      true,
      false,
      42,
      3.14,
      "hello world"
    ]

    for value <- examples do
      encoded = Encoder.encode(value)
      decoded = Decoder.decode(encoded)
      IO.puts("  #{inspect(value)} -> #{inspect(encoded)} -> #{inspect(decoded)}")
    end

    IO.puts("")
  end

  defp demonstrate_special_floats do
    IO.puts("--- Special Floats ---")

    examples = [
      :infinity,
      :neg_infinity,
      :nan
    ]

    for value <- examples do
      encoded = Encoder.encode(value)
      decoded = Decoder.decode(encoded)
      IO.puts("  #{inspect(value)} -> #{inspect(encoded)} -> #{inspect(decoded)}")
    end

    IO.puts("")
  end

  defp demonstrate_tuples do
    IO.puts("--- Tuples ---")

    examples = [
      {},
      {1, 2, 3},
      {"name", 42, true},
      {:ok, "result"}
    ]

    for value <- examples do
      encoded = Encoder.encode(value)
      decoded = Decoder.decode(encoded)
      IO.puts("  #{inspect(value)} -> #{inspect(encoded)}")
      IO.puts("    -> #{inspect(decoded)}")
    end

    IO.puts("")
  end

  defp demonstrate_sets do
    IO.puts("--- Sets (MapSet) ---")

    examples = [
      MapSet.new(),
      MapSet.new([1, 2, 3]),
      MapSet.new(["a", "b", "c"])
    ]

    for value <- examples do
      encoded = Encoder.encode(value)
      decoded = Decoder.decode(encoded)
      IO.puts("  #{inspect(value)} -> #{inspect(encoded)}")
      IO.puts("    -> #{inspect(decoded)}")
    end

    IO.puts("")
  end

  defp demonstrate_datetime do
    IO.puts("--- Date/Time Types ---")

    {:ok, dt} = DateTime.new(~D[2024-12-24], ~T[10:30:00])
    date = ~D[2024-12-24]
    time = ~T[10:30:00]

    examples = [
      {:datetime, dt},
      {:date, date},
      {:time, time}
    ]

    for {label, value} <- examples do
      encoded = Encoder.encode(value)
      decoded = Decoder.decode(encoded)
      IO.puts("  #{label}: #{inspect(value)}")
      IO.puts("    encoded: #{inspect(encoded)}")
      IO.puts("    decoded: #{inspect(decoded)}")
    end

    IO.puts("")
  end

  defp demonstrate_nested_structures do
    IO.puts("--- Nested Structures ---")

    nested = %{
      "user" => %{
        "name" => "Alice",
        "scores" => [100, 95, 88]
      },
      "status" => {:ok, "active"},
      "tags" => MapSet.new(["admin", "verified"])
    }

    encoded = Encoder.encode(nested)
    decoded = Decoder.decode(encoded)

    IO.puts("  Original: #{inspect(nested)}")
    IO.puts("")
    IO.puts("  Encoded:")
    IO.puts("    #{Jason.encode!(encoded, pretty: true) |> String.replace("\n", "\n    ")}")
    IO.puts("")
    IO.puts("  Decoded: #{inspect(decoded)}")
    IO.puts("")
  end

  defp demonstrate_round_trip do
    IO.puts("--- Round-Trip Verification ---")

    test_values = [
      nil,
      true,
      42,
      3.14,
      "hello",
      :infinity,
      {1, 2, 3},
      MapSet.new([1, 2, 3]),
      [1, [2, [3]]],
      %{"a" => %{"b" => "c"}}
    ]

    all_passed =
      test_values
      |> Enum.all?(fn value ->
        encoded = Encoder.encode(value)
        decoded = Decoder.decode(encoded)
        passed = decoded == value

        status = if passed, do: "✓", else: "✗"
        IO.puts("  #{status} #{inspect(value)}")

        passed
      end)

    if all_passed do
      IO.puts("\n  All round-trips successful!")
    else
      IO.puts("\n  Some round-trips failed!")
    end
  end
end

TypesDemo.run()
