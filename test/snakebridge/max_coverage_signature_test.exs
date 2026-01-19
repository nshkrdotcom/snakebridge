defmodule SnakeBridge.MaxCoverageSignatureTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Introspector
  alias SnakeBridge.TestHelpers

  setup context do
    TestHelpers.skip_unless_python(context)

    fixtures_path = Path.expand("../fixtures/python", __DIR__)
    stubs_path = Path.expand("../fixtures/stubs/types-fixture_types_pkg", __DIR__)
    typeshed_path = Path.expand("../fixtures/typeshed", __DIR__)
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    original_pythonpath = System.get_env("PYTHONPATH")

    pythonpath =
      [fixtures_path, stubs_path, original_pythonpath]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    System.put_env("PYTHONPATH", pythonpath)

    original_signature_sources = Application.get_env(:snakebridge, :signature_sources)
    original_stub_search_paths = Application.get_env(:snakebridge, :stub_search_paths)
    original_use_typeshed = Application.get_env(:snakebridge, :use_typeshed)
    original_typeshed_path = Application.get_env(:snakebridge, :typeshed_path)
    original_stubgen = Application.get_env(:snakebridge, :stubgen)

    Application.put_env(
      :snakebridge,
      :signature_sources,
      [:runtime, :text_signature, :runtime_hints, :stub, :stubgen, :variadic]
    )

    Application.put_env(:snakebridge, :stub_search_paths, [])
    Application.put_env(:snakebridge, :use_typeshed, false)
    Application.put_env(:snakebridge, :typeshed_path, typeshed_path)

    Application.put_env(
      :snakebridge,
      :stubgen,
      enabled: true,
      cache_dir: Path.join(System.tmp_dir!(), "snakebridge_stubgen_cache")
    )

    on_exit(fn ->
      restore_env("PYTHONPATH", original_pythonpath)
      restore_app_env(:snakebridge, :signature_sources, original_signature_sources)
      restore_app_env(:snakebridge, :stub_search_paths, original_stub_search_paths)
      restore_app_env(:snakebridge, :use_typeshed, original_use_typeshed)
      restore_app_env(:snakebridge, :typeshed_path, original_typeshed_path)
      restore_app_env(:snakebridge, :stubgen, original_stubgen)
    end)

    :ok
  end

  test "runtime signatures use runtime tier" do
    library = %SnakeBridge.Config.Library{
      name: :fixture_runtime,
      python_name: "fixture_runtime",
      module_name: FixtureRuntime
    }

    {:ok, result} = Introspector.introspect(library, ["add"])
    info = find_function(result, "add")

    assert info["signature_source"] == "runtime"
    assert info["doc_source"] == "runtime"
  end

  test "text signature tier is used when inspect.signature fails" do
    library = %SnakeBridge.Config.Library{
      name: :fixture_textsig,
      python_name: "fixture_textsig",
      module_name: FixtureTextsig
    }

    {:ok, result} = Introspector.introspect(library, ["text_sig_func"])
    info = find_function(result, "text_sig_func")

    assert info["signature_source"] == "text_signature"
    assert Enum.map(info["parameters"], & &1["name"]) == ["a", "b", "c"]
  end

  test "runtime hints tier is used when only annotations are available" do
    library = %SnakeBridge.Config.Library{
      name: :fixture_runtime_hints,
      python_name: "fixture_runtime_hints",
      module_name: FixtureRuntimeHints
    }

    {:ok, result} = Introspector.introspect(library, ["hint_only"])
    info = find_function(result, "hint_only")

    assert info["signature_source"] == "runtime_hints"
    assert Enum.map(info["parameters"], & &1["name"]) == ["a", "b"]
  end

  test "local stub files provide signatures and docs" do
    library = %SnakeBridge.Config.Library{
      name: :fixture_stubonly,
      python_name: "fixture_stubonly",
      module_name: FixtureStubonly
    }

    {:ok, result} = Introspector.introspect(library, ["stub_add", "stub_doc_only"])
    stub_add = find_function(result, "stub_add")
    stub_doc = find_function(result, "stub_doc_only")

    assert stub_add["signature_source"] == "stub"
    assert stub_doc["doc_source"] == "stub"
    assert stub_doc["docstring"] =~ "Docstring from stub"
  end

  test "stub overloads record overload metadata" do
    library = %SnakeBridge.Config.Library{
      name: :fixture_overloads,
      python_name: "fixture_overloads",
      module_name: FixtureOverloads
    }

    {:ok, result} = Introspector.introspect(library, ["parse"])
    info = find_function(result, "parse")

    assert info["signature_source"] == "stub"
    assert info["overload_count"] == 2
  end

  test "types- packages are used when installed" do
    library = %SnakeBridge.Config.Library{
      name: :fixture_types_pkg,
      python_name: "fixture_types_pkg",
      module_name: FixtureTypesPkg
    }

    {:ok, result} = Introspector.introspect(library, ["typed_func"])
    info = find_function(result, "typed_func")

    assert info["signature_source"] == "stub"
    assert info["signature_detail"] =~ "types-"
  end

  test "typeshed lookup provides stubs when enabled" do
    Application.put_env(:snakebridge, :use_typeshed, true)

    library = %SnakeBridge.Config.Library{
      name: :fixture_typeshed,
      python_name: "fixture_typeshed",
      module_name: FixtureTypeshed,
      use_typeshed: true
    }

    {:ok, result} = Introspector.introspect(library, ["typeshed_func"])
    info = find_function(result, "typeshed_func")

    assert info["signature_source"] == "stub"
    assert info["signature_detail"] =~ "typeshed"
  end

  test "stubgen fallback is used when stubs are missing" do
    library = %SnakeBridge.Config.Library{
      name: :fixture_stubgen,
      python_name: "fixture_stubgen",
      module_name: FixtureStubgen,
      signature_sources: [:stubgen, :variadic]
    }

    {:ok, result} = Introspector.introspect(library, ["generated"])
    info = find_function(result, "generated")

    assert info["signature_source"] == "stubgen"
    assert is_binary(info["signature_detail"])
  end

  test "variadic fallback is only used when no other sources are allowed" do
    library = %SnakeBridge.Config.Library{
      name: :fixture_variadic,
      python_name: "fixture_variadic",
      module_name: FixtureVariadic,
      signature_sources: [:variadic]
    }

    {:ok, result} = Introspector.introspect(library, ["variadic_only"])
    info = find_function(result, "variadic_only")

    assert info["signature_source"] == "variadic"
    assert info["signature_missing_reason"] != nil
  end

  defp find_function(result, name) do
    Enum.find(result["functions"], fn info -> info["name"] == name end)
  end

  defp restore_env(_var, nil), do: System.delete_env("PYTHONPATH")
  defp restore_env(var, value), do: System.put_env(var, value)

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)
end
