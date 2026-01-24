defmodule SnakeBridge.ModuleModeIntrospectionTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias SnakeBridge.Introspector
  alias SnakeBridge.Config

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

  defp base_library(overrides) do
    struct(
      Config.Library,
      [
        name: :fixture_module_modes,
        python_name: "fixture_module_modes",
        module_name: FixtureModuleModes,
        generate: :all
      ] ++ overrides
    )
  end

  test "public mode includes public modules and packages, skips private and empty modules" do
    library = base_library(module_mode: :public)

    {:ok, result} = Introspector.introspect_module(library)
    namespaces = Map.get(result, "namespaces", %{})

    assert Map.has_key?(namespaces, "alpha")
    assert Map.has_key?(namespaces, "pkg")
    assert Map.has_key?(namespaces, "pkg.child")
    assert Map.has_key?(namespaces, "broken_pkg")

    refute Map.has_key?(namespaces, "_private")
    refute Map.has_key?(namespaces, "empty_mod")

    assert is_binary(get_in(namespaces, ["broken_pkg", "error"]))
  end

  test "module_depth limits nested submodules" do
    library = base_library(module_mode: :public, module_depth: 1)

    {:ok, result} = Introspector.introspect_module(library)
    namespaces = Map.get(result, "namespaces", %{})

    assert Map.has_key?(namespaces, "pkg")
    refute Map.has_key?(namespaces, "pkg.child")
  end

  test "module_include overrides public filtering" do
    library = base_library(module_mode: :public, module_include: ["empty_mod"])

    {:ok, result} = Introspector.introspect_module(library)
    namespaces = Map.get(result, "namespaces", %{})

    assert Map.has_key?(namespaces, "empty_mod")
  end
end
