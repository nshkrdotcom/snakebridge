#!/usr/bin/env elixir
#
# GenAI Streaming Example - Google Gemini with live token streaming
# Run: elixir examples/genai_streaming.exs

Code.require_file("example_helpers.exs", __DIR__)

# Check for API key
unless System.get_env("GEMINI_API_KEY") do
  IO.puts("\n❌ GEMINI_API_KEY environment variable not set!\n")
  IO.puts("Get your key: https://aistudio.google.com/app/apikey")
  IO.puts("Then run: export GEMINI_API_KEY='your-key-here'\n")
  System.halt(1)
end

SnakeBridgeExample.setup(
  python_packages: ["google-genai"],
  adapter: "adapters.genai.adapter.GenAIAdapter",
  description: "Google Gemini AI - Streaming Text Generation"
)

SnakeBridgeExample.run(fn ->
  IO.puts("🤖 Discovering Google GenAI library...")

  {:ok, schema} = SnakeBridge.discover("google.genai")

  IO.puts("✓ GenAI discovered!")
  IO.puts("  Version: #{schema["library_version"]}")
  IO.puts("  Classes: #{map_size(schema["classes"])}")
  IO.puts("  Functions: #{map_size(schema["functions"])}")

  IO.puts("\n🚀 Calling Gemini API...")

  _api_key = System.get_env("GEMINI_API_KEY")
  session_id = "genai_demo_#{:rand.uniform(10000)}"

  IO.puts("\n💬 Generating text with gemini-2.0-flash-exp...")

  prompt = """
  Write a detailed technical explanation of how Elixir and Python complement each other in software engineering.
  Cover these topics with at least 2-3 sentences each:
  1. Elixir's concurrency vs Python's data science libraries
  2. Use cases for combining them
  3. Architecture patterns (Elixir as orchestrator, Python as worker)
  4. Real-world integration examples
  5. Performance considerations
  6. Developer experience benefits
  7. Deployment strategies
  8. Testing approaches

  Write in a clear, technical style. Make it comprehensive - at least 15-20 sentences total.
  """

  IO.puts("   (Requesting long-form content to demonstrate streaming...)")
  IO.puts("\n📡 Calling Gemini API...\n")

  # Call the GenAI adapter's generate_text tool
  result =
    SnakeBridge.Runtime.snakepit_adapter().execute_in_session(
      session_id,
      "generate_text",
      %{
        "model" => "gemini-2.0-flash-exp",
        "prompt" => prompt
      }
    )

  case result do
    {:ok, %{"success" => true, "text" => text}} ->
      IO.puts("✨ Response from Gemini:")
      IO.puts(String.duplicate("─", 60))
      IO.puts(text)
      IO.puts(String.duplicate("─", 60))
      IO.puts("\n✅ Success! Called Google Gemini AI from Elixir!")

    {:ok, %{"success" => false, "error" => error}} ->
      IO.puts("✗ API Error: #{error}")

    {:error, reason} ->
      IO.puts("✗ Call failed: #{inspect(reason)}")
  end
end)
