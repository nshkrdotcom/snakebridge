defmodule SnakeBridge.ManifestFileTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Manifest

  test "loads JSON manifest files into config" do
    manifest = %{
      "name" => "example",
      "python_module" => "example",
      "python_path_prefix" => "snakebridge_adapter.example_bridge",
      "elixir_module" => "SnakeBridge.Example",
      "functions" => [
        %{"name" => "ping", "args" => ["text"], "returns" => "string"}
      ]
    }

    path = Path.join(System.tmp_dir!(), "snakebridge_manifest_test.json")
    File.write!(path, Jason.encode!(manifest))

    on_exit(fn -> File.rm(path) end)

    assert {:ok, config} = Manifest.from_file(path)
    assert config.python_module == "example"
    assert [%{name: "ping"}] = config.functions
  end
end
