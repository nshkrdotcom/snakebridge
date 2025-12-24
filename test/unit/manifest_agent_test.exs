defmodule SnakeBridge.ManifestAgentTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Manifest.Agent

  test "suggest_from_schema returns a manifest with functions" do
    schema = %{
      "library_version" => "1.0.0",
      "functions" => %{
        "add" => %{
          "name" => "add",
          "docstring" => "Add two numbers",
          "parameters" => [
            %{"name" => "a", "type" => "int"},
            %{"name" => "b", "type" => "int"}
          ],
          "return_type" => "int"
        },
        "read_file" => %{
          "name" => "read_file",
          "docstring" => "Read a file",
          "parameters" => [%{"name" => "path", "type" => "str"}],
          "return_type" => "str"
        }
      }
    }

    manifest = Agent.suggest_from_schema(schema, "example", limit: 5)

    assert manifest["python_module"] == "example"
    assert manifest["version"] == "1.0.0"

    functions = Map.get(manifest, "functions")
    assert is_list(functions)
    assert Enum.any?(functions, fn entry -> entry["name"] == "add" end)
    refute Enum.any?(functions, fn entry -> entry["name"] == "read_file" end)
  end
end
