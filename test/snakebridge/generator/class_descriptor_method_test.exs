defmodule SnakeBridge.Generator.ClassDescriptorMethodTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  @library %SnakeBridge.Config.Library{
    name: :descriptor_fixture,
    python_name: "descriptor_fixture",
    module_name: DescriptorFixture
  }

  test "classmethods and staticmethods are generated without an instance ref" do
    class_info = %{
      "name" => "DescriptorDemo",
      "python_module" => "descriptor_fixture",
      "methods" => [
        %{"name" => "__init__", "parameters" => []},
        %{
          "name" => "from_value",
          "method_kind" => "classmethod",
          "parameters" => [
            %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"},
            %{"name" => "scale", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "2"}
          ],
          "return_type" => %{"type" => "any"}
        },
        %{
          "name" => "add",
          "method_kind" => "staticmethod",
          "parameters" => [
            %{"name" => "left", "kind" => "POSITIONAL_OR_KEYWORD"},
            %{"name" => "right", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "1"}
          ],
          "return_type" => %{"type" => "int"}
        },
        %{
          "name" => "run",
          "method_kind" => "instance",
          "parameters" => [
            %{"name" => "self", "kind" => "POSITIONAL_OR_KEYWORD"},
            %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"}
          ],
          "return_type" => %{"type" => "any"}
        }
      ],
      "attributes" => ["doubled"]
    }

    source = Generator.render_class(class_info, @library)
    Code.string_to_quoted!(source)

    assert source =~ "def from_value(value) do"
    assert source =~ "def from_value(value, opts) when"
    assert source =~ "def from_value(value, scale) do"
    assert source =~ "def from_value(value, scale, opts) when"

    assert source =~
             "SnakeBridge.Runtime.call_class_method(__MODULE__, :from_value, [value], [])"

    assert source =~
             "SnakeBridge.Runtime.call_class_method(__MODULE__, :from_value, [value, scale], opts)"

    refute source =~ "def from_value(ref"

    assert source =~ "def add(left) do"
    assert source =~ "def add(left, opts) when"
    assert source =~ "def add(left, right) do"
    assert source =~ "SnakeBridge.Runtime.call_class_method(__MODULE__, :add, [left], [])"
    refute source =~ "def add(ref"

    assert source =~ "def run(ref, value"
    assert source =~ "SnakeBridge.Runtime.call_method(ref, :run, [value], opts)"

    assert source =~ "def doubled(ref) do"
    assert source =~ "SnakeBridge.Runtime.get_attr(ref, :doubled)"
  end

  test "class-bound positional prefixes validate required keyword-only arguments" do
    class_info = %{
      "name" => "DescriptorDemo",
      "python_module" => "descriptor_fixture",
      "methods" => [
        %{"name" => "__init__", "parameters" => []},
        %{
          "name" => "build",
          "method_kind" => "classmethod",
          "parameters" => [
            %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"},
            %{"name" => "scale", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "2"},
            %{"name" => "mode", "kind" => "KEYWORD_ONLY"}
          ],
          "return_type" => %{"type" => "any"}
        }
      ],
      "attributes" => []
    }

    source = Generator.render_class(class_info, @library)
    Code.string_to_quoted!(source)

    assert source =~ "def build(value) do"
    assert source =~ "kw_keys = [] |> Keyword.keys()"
    assert source =~ "def build(value, opts) when"
    assert source =~ "kw_keys = opts |> Keyword.keys()"
    refute source =~ "def build(ref"
  end
end
