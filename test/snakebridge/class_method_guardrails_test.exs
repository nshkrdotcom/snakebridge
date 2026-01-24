defmodule SnakeBridge.ClassMethodGuardrailsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias SnakeBridge.Config
  alias SnakeBridge.Introspector

  @fixtures_path Path.expand("../fixtures/python", __DIR__)

  setup do
    original_config = Application.get_env(:snakebridge, :introspector, [])

    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    pythonpath =
      [@fixtures_path, System.get_env("PYTHONPATH")]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    Application.put_env(:snakebridge, :introspector, env: %{"PYTHONPATH" => pythonpath})

    on_exit(fn ->
      Application.put_env(:snakebridge, :introspector, original_config)
    end)

    :ok
  end

  test "max_class_methods falls back to defined-only methods" do
    library =
      struct(Config.Library,
        name: :fixture_method_guardrails,
        python_name: "fixture_method_guardrails",
        module_name: FixtureMethodGuardrails,
        generate: :all,
        class_method_scope: :all,
        max_class_methods: 5
      )

    assert {:ok, result} = Introspector.introspect_module(library)

    classes =
      case result do
        %{"classes" => classes} when is_list(classes) ->
          classes

        %{"namespaces" => namespaces} when is_map(namespaces) ->
          namespaces
          |> Map.values()
          |> Enum.flat_map(&List.wrap(&1["classes"]))

        _ ->
          []
      end

    derived = Enum.find(classes, &(&1["name"] == "Derived"))
    assert is_map(derived)
    assert derived["methods_truncated"] == true
    assert derived["method_scope"] == "defined"

    method_names = derived["methods"] |> List.wrap() |> Enum.map(& &1["name"])

    assert "__init__" in method_names
    assert "derived_method" in method_names
    refute Enum.any?(method_names, &String.starts_with?(&1, "base_method_"))
  end
end
