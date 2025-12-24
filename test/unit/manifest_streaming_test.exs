defmodule SnakeBridge.ManifestStreamingTest do
  use ExUnit.Case, async: true

  test "streaming functions generate *_stream variants" do
    config = %SnakeBridge.Config{
      python_module: "test",
      functions: [
        %{
          name: "stream_me",
          python_path: "test.stream_me",
          elixir_name: :stream_me,
          streaming: true,
          elixir_module: StreamTestModule
        }
      ]
    }

    {:ok, [module]} = SnakeBridge.generate(config)

    assert function_exported?(module, :stream_me_stream, 0) or
             function_exported?(module, :stream_me_stream, 1) or
             function_exported?(module, :stream_me_stream, 2)
  end
end
