defmodule SnakeBridge.MethodKindIntrospectionTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Config
  alias SnakeBridge.Introspector
  alias SnakeBridge.TestHelpers

  @fixtures_path Path.expand("../fixtures/python", __DIR__)

  setup context do
    TestHelpers.skip_unless_python(context)

    original_config = Application.get_env(:snakebridge, :introspector, [])
    original_pythonpath = System.get_env("PYTHONPATH")
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    pythonpath =
      [@fixtures_path, original_pythonpath]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    Application.put_env(:snakebridge, :introspector, env: %{"PYTHONPATH" => pythonpath})
    System.put_env("PYTHONPATH", pythonpath)

    on_exit(fn ->
      Application.put_env(:snakebridge, :introspector, original_config)

      if original_pythonpath in [nil, ""] do
        System.delete_env("PYTHONPATH")
      else
        System.put_env("PYTHONPATH", original_pythonpath)
      end
    end)

    :ok
  end

  test "runtime and stub introspection preserve classmethod and staticmethod binding kinds" do
    library = %Config.Library{
      name: :fixture_method_kinds,
      python_name: "fixture_method_kinds",
      module_name: FixtureMethodKinds
    }

    assert {:ok, result} =
             Introspector.introspect(
               library,
               ["DescriptorDemo", "StubOnlyDescriptor"]
             )

    runtime_class = find_class!(result, "DescriptorDemo")
    runtime_methods = methods_by_name(runtime_class)

    assert runtime_methods["__init__"]["method_kind"] == "instance"
    assert runtime_methods["instance_value"]["method_kind"] == "instance"
    assert runtime_methods["from_value"]["method_kind"] == "classmethod"
    assert runtime_methods["add"]["method_kind"] == "staticmethod"

    assert Enum.map(runtime_methods["from_value"]["parameters"], & &1["name"]) == [
             "value",
             "scale"
           ]

    assert Enum.map(runtime_methods["add"]["parameters"], & &1["name"]) == [
             "left",
             "right"
           ]

    assert "doubled" in runtime_class["attributes"]

    stub_class = find_class!(result, "StubOnlyDescriptor")
    stub_methods = methods_by_name(stub_class)

    assert stub_methods["from_name"]["method_kind"] == "classmethod"
    assert stub_methods["normalize"]["method_kind"] == "staticmethod"
    assert Enum.map(stub_methods["from_name"]["parameters"], & &1["name"]) == ["name"]

    assert Enum.map(stub_methods["normalize"]["parameters"], & &1["name"]) == [
             "value",
             "prefix"
           ]
  end

  defp find_class!(result, name) do
    result["classes"]
    |> Enum.find(&(&1["name"] == name))
    |> case do
      nil -> flunk("missing class #{name}: #{inspect(result)}")
      class_info -> class_info
    end
  end

  defp methods_by_name(class_info) do
    class_info["methods"]
    |> List.wrap()
    |> Map.new(&{&1["name"], &1})
  end
end
