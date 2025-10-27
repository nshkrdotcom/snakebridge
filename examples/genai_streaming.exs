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

  api_key = System.get_env("GEMINI_API_KEY")
  session_id = "genai_demo_#{:rand.uniform(10000)}"

  IO.puts("\n💬 Generating text with gemini-2.0-flash-exp...")

  IO.puts(
    "   Prompt: 'Explain how Elixir and Python complement each other in 5 short paragraphs'"
  )

  IO.puts("\n📡 Calling Gemini API...\n")

  # Call the GenAI adapter's generate_text tool
  result =
    SnakeBridge.Runtime.snakepit_adapter().execute_in_session(
      session_id,
      "generate_text",
      %{
        "model" => "gemini-2.0-flash-exp",
        "prompt" =>
          "Explain how Elixir and Python complement each other. Write exactly 5 short paragraphs."
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
