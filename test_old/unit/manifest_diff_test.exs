defmodule SnakeBridge.ManifestDiffTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Manifest.Diff

  test "diff detects missing and new functions" do
    config = %SnakeBridge.Config{
      python_module: "example",
      functions: [
        %{name: "alpha"},
        %{name: "beta"}
      ]
    }

    schema = %{
      "functions" => %{
        "alpha" => %{},
        "gamma" => %{}
      }
    }

    diff = Diff.diff(config, schema)

    assert diff.missing_in_schema == ["beta"]
    assert diff.new_in_schema == ["gamma"]
    assert diff.common == ["alpha"]
  end
end
