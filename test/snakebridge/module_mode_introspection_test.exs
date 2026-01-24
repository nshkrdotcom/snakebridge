defmodule SnakeBridge.ModuleModeIntrospectionTest do
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

  test "exports mode includes only explicitly-exported submodules" do
    library =
      base_library(
        name: :fixture_exports_mode,
        python_name: "fixture_exports_mode",
        module_name: FixtureExportsMode,
        module_mode: :exports
      )

    {:ok, result} = Introspector.introspect_module(library)
    namespaces = Map.get(result, "namespaces", %{})

    assert Map.has_key?(namespaces, "api_mod")

    refute Map.has_key?(namespaces, "internal_mod")
    refute Map.has_key?(namespaces, "internal_pkg")
    refute Map.has_key?(namespaces, "internal_pkg.deep")
  end

  test "explicit mode includes only modules/packages defining __all__" do
    library =
      base_library(
        name: :fixture_explicit_mode,
        python_name: "fixture_explicit_mode",
        module_name: FixtureExplicitMode,
        module_mode: :explicit
      )

    {:ok, result} = Introspector.introspect_module(library)
    namespaces = Map.get(result, "namespaces", %{})

    assert Map.has_key?(namespaces, "beta")
    assert Map.has_key?(namespaces, "pkg")
    assert Map.has_key?(namespaces, "pkg.child")

    refute Map.has_key?(namespaces, "alpha")
    refute Map.has_key?(namespaces, "pkg.noall")
  end
end
