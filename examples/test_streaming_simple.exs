#!/usr/bin/env elixir
# Simple test to see if Snakepit streaming actually works

Code.require_file("example_helpers.exs", __DIR__)

SnakeBridgeExample.setup(
  python_packages: [],
  adapter: "snakepit_bridge.adapters.showcase.showcase_adapter.ShowcaseAdapter",
  description: "Test Basic Streaming"
)

SnakeBridgeExample.run(fn ->
  IO.puts("🧪 Testing if Snakepit streaming works at all...\n")

  session_id = "stream_test_#{:rand.uniform(10000)}"

  # Try to call the showcase adapter's stream_progress
  IO.puts("Calling stream_progress (should yield 5 chunks)...")

  result =
    Snakepit.execute_in_session_stream(
      session_id,
      "stream_progress",
      %{"steps" => 5},
      fn chunk ->
        IO.inspect(chunk, label: "Received chunk")
      end
    )

  case result do
    :ok ->
      IO.puts("\n✅ Streaming works!")

    {:error, reason} ->
      IO.puts("\n❌ Streaming failed: #{inspect(reason)}")
  end
end)
