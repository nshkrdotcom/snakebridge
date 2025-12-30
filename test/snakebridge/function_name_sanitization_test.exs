defmodule SnakeBridge.FunctionNameSanitizationTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  test "render_function sanitizes reserved words and preserves python name" do
    info = %{
      "name" => "class",
      "parameters" => [],
      "docstring" => "Reserved name."
    }

    library = %SnakeBridge.Config.Library{
      name: :reserved,
      python_name: "reserved",
      module_name: Reserved,
      streaming: []
    }

    source = Generator.render_function(info, library)

    assert source =~ "def py_class("
    assert source =~ "SnakeBridge.Runtime.call(__MODULE__, \"class\""
  end
end
