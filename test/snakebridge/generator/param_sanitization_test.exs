defmodule SnakeBridge.Generator.ParamSanitizationTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  test "leading underscore params are normalized to avoid unused warnings" do
    info = %{
      "name" => "model_rebuild",
      "parameters" => [
        %{"name" => "_parent_namespace_depth", "kind" => "POSITIONAL_OR_KEYWORD"}
      ],
      "docstring" => ""
    }

    library = %SnakeBridge.Config.Library{
      name: :dspy,
      python_name: "dspy",
      module_name: Dspy,
      streaming: []
    }

    source = Generator.render_function(info, library)

    assert source =~ "def model_rebuild(parent_namespace_depth"
    refute source =~ "_parent_namespace_depth"
  end
end
