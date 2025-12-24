defmodule SnakeBridge.ManifestTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Manifest

  test "manifest map converts to config with prefixed python paths" do
    manifest = %{
      python_module: "example",
      python_path_prefix: "snakebridge_adapter.example_bridge",
      elixir_module: "SnakeBridge.Example",
      functions: [
        {:ping, args: [:text], returns: :string}
      ]
    }

    config = Manifest.to_config(manifest)

    assert config.python_module == "example"
    assert length(config.functions) == 1

    [func] = config.functions
    assert func.name == "ping"
    assert func.python_path == "snakebridge_adapter.example_bridge.ping"
    assert func.elixir_name == :ping
    assert func.elixir_module == SnakeBridge.Example
  end
end
