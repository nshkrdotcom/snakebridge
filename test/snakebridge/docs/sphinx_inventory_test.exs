defmodule SnakeBridge.Docs.SphinxInventoryTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Docs.SphinxInventory

  test "parses inventory header and entries" do
    lines = [
      "examplelib py:module 1 api/examplelib.html -",
      "examplelib.config py:module 1 api/examplelib.config.html -",
      "examplelib.config.Config py:class 1 api/generated/$ -",
      "examplelib.config.load_config py:function 1 api/examplelib.config.load_config.html -",
      "examplelib.Client.generate py:method 1 api/examplelib.Client.generate.html -"
    ]

    decompressed = Enum.join(lines, "\n") <> "\n"
    compressed = :zlib.compress(decompressed)

    content =
      [
        "# Sphinx inventory version 2",
        "# Project: ExampleLib",
        "# Version: 1.0.0",
        "# The remainder of this file is compressed using zlib."
      ]
      |> Enum.join("\n")
      |> Kernel.<>("\n")
      |> Kernel.<>(compressed)

    assert {:ok, inventory} = SphinxInventory.parse(content)
    assert inventory.project == "ExampleLib"
    assert inventory.version == "1.0.0"

    assert Enum.any?(inventory.entries, fn entry ->
             entry.name == "examplelib.config.Config" and entry.domain_role == "py:class" and
               entry.uri == "api/generated/examplelib.config.Config" and
               entry.dispname == "examplelib.config.Config"
           end)
  end
end
