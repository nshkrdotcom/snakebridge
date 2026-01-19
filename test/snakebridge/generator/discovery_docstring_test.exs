defmodule SnakeBridge.Generator.DiscoveryDocstringTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Config.Library
  alias SnakeBridge.Generator

  test "render_library keeps long class docstrings intact in discovery output" do
    long_doc = "START-" <> String.duplicate("a", 5000) <> "-TAIL"

    library = %Library{
      name: :demo,
      version: "0.1.0",
      module_name: Demo,
      python_name: "demo"
    }

    class_info = %{
      "name" => "HugeDoc",
      "docstring" => long_doc,
      "methods" => [],
      "attributes" => []
    }

    source = Generator.render_library(library, [], [class_info], version: "0.0.0")

    assert source =~ "START-"
    assert source =~ "-TAIL"
    refute source =~ ~r/<>\\s*\\.\\.\\./
  end
end
