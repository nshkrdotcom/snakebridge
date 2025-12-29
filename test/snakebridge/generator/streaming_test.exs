defmodule SnakeBridge.Generator.StreamingTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "render_function/2 with streaming" do
    test "streaming function generates both normal and stream variants" do
      info = %{
        "name" => "generate",
        "parameters" => [
          %{"name" => "prompt", "kind" => "POSITIONAL_OR_KEYWORD"}
        ],
        "docstring" => "Generate text from prompt."
      }

      library = %SnakeBridge.Config.Library{
        name: :llm,
        python_name: "llm",
        module_name: Llm,
        # This function is streaming
        streaming: ["generate"]
      }

      source = Generator.render_function(info, library)

      # Normal variant
      assert source =~ "def generate(prompt"

      # Streaming variant
      assert source =~ "def generate_stream("
      assert source =~ "when is_function(callback, 1)"
      assert source =~ "SnakeBridge.Runtime.stream("

      # Streaming variant has @spec
      assert source =~ "@spec generate_stream("
      assert source =~ ":: :ok | {:error, Snakepit.Error.t()}"
    end

    test "streaming variant always accepts opts for runtime flags" do
      info = %{
        "name" => "stream_data",
        "parameters" => [
          %{"name" => "source", "kind" => "POSITIONAL_OR_KEYWORD"}
        ],
        "docstring" => "Stream data."
      }

      library = %SnakeBridge.Config.Library{
        name: :data,
        python_name: "data",
        module_name: Data,
        streaming: ["stream_data"]
      }

      source = Generator.render_function(info, library)

      # Streaming variant must accept opts even if Python has no optional params
      assert source =~ "def stream_data_stream(source, opts \\\\ [], callback)"
    end

    test "non-streaming function does not generate stream variant" do
      info = %{
        "name" => "compute",
        "parameters" => [%{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"}],
        "docstring" => "Compute."
      }

      library = %SnakeBridge.Config.Library{
        name: :math,
        python_name: "math",
        module_name: Math,
        # No streaming functions
        streaming: []
      }

      source = Generator.render_function(info, library)

      assert source =~ "def compute(x"
      refute source =~ "def compute_stream("
    end
  end
end
