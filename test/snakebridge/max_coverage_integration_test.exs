defmodule SnakeBridge.MaxCoverageIntegrationTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Compiler.Pipeline
  alias SnakeBridge.Config
  alias SnakeBridge.Config.Library
  alias SnakeBridge.TestHelpers

  @tag :tmp_dir
  test "compile generate: :all uses stub metadata in manifest and wrappers", %{tmp_dir: tmp_dir} do
    TestHelpers.ensure_python!()

    fixtures_path = Path.expand("../fixtures/python", __DIR__)
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    pythonpath =
      [fixtures_path, System.get_env("PYTHONPATH")]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    library = %Library{
      name: :fixture_stubonly,
      version: :stdlib,
      module_name: FixtureStubonly,
      python_name: "fixture_stubonly",
      generate: :all
    }

    generated_dir = Path.join(tmp_dir, "generated")
    metadata_dir = Path.join(tmp_dir, "metadata")
    report_dir = Path.join(tmp_dir, "reports")

    config = %Config{
      libraries: [library],
      auto_install: :never,
      generated_dir: generated_dir,
      metadata_dir: metadata_dir,
      helper_paths: [],
      helper_pack_enabled: false,
      helper_allowlist: [],
      inline_enabled: false,
      strict: false,
      verbose: false,
      scan_paths: [],
      scan_exclude: [],
      introspector: [env: %{"PYTHONPATH" => pythonpath}],
      docs: [],
      runtime_client: Snakepit,
      ledger: [],
      coverage_report: [output_dir: report_dir]
    }

    original_registry_path = Application.get_env(:snakebridge, :registry_path)
    Application.put_env(:snakebridge, :registry_path, Path.join(tmp_dir, "registry.json"))

    on_exit(fn ->
      restore_app_env(:snakebridge, :registry_path, original_registry_path)
    end)

    File.cd!(tmp_dir, fn ->
      assert {:ok, []} = Pipeline.run(config)
    end)

    manifest_path = Path.join(metadata_dir, "manifest.json")
    manifest = manifest_path |> File.read!() |> Jason.decode!()

    entry = manifest["symbols"]["FixtureStubonly.stub_doc_only/1"]
    assert entry["signature_source"] == "stub"
    assert entry["doc_source"] == "stub"

    generated_path = Path.join(generated_dir, "fixture_stubonly.ex")
    generated = File.read!(generated_path)
    assert generated =~ "def stub_add(a, b"
    assert generated =~ "Docstring from stub only"
  end

  @tag :tmp_dir
  test "strict signature thresholds fail for variadic symbols", %{tmp_dir: tmp_dir} do
    TestHelpers.ensure_python!()

    fixtures_path = Path.expand("../fixtures/python", __DIR__)
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    pythonpath =
      [fixtures_path, System.get_env("PYTHONPATH")]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    library = %Library{
      name: :fixture_variadic,
      version: :stdlib,
      module_name: FixtureVariadic,
      python_name: "fixture_variadic",
      generate: :all,
      signature_sources: [:variadic],
      strict_signatures: true,
      min_signature_tier: :stub
    }

    config = %Config{
      libraries: [library],
      auto_install: :never,
      generated_dir: Path.join(tmp_dir, "generated"),
      metadata_dir: Path.join(tmp_dir, "metadata"),
      helper_paths: [],
      helper_pack_enabled: false,
      helper_allowlist: [],
      inline_enabled: false,
      strict: false,
      verbose: false,
      scan_paths: [],
      scan_exclude: [],
      introspector: [env: %{"PYTHONPATH" => pythonpath}],
      docs: [],
      runtime_client: Snakepit,
      ledger: []
    }

    File.cd!(tmp_dir, fn ->
      assert_raise SnakeBridge.CompileError, ~r/signature tier/i, fn ->
        Pipeline.run(config)
      end
    end)
  end

  @tag :tmp_dir
  test "coverage report is written for library", %{tmp_dir: tmp_dir} do
    TestHelpers.ensure_python!()

    fixtures_path = Path.expand("../fixtures/python", __DIR__)
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    pythonpath =
      [fixtures_path, System.get_env("PYTHONPATH")]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    library = %Library{
      name: :fixture_runtime,
      version: :stdlib,
      module_name: FixtureRuntime,
      python_name: "fixture_runtime",
      generate: :all
    }

    generated_dir = Path.join(tmp_dir, "generated")
    metadata_dir = Path.join(tmp_dir, "metadata")
    report_dir = Path.join(tmp_dir, "reports")

    config = %Config{
      libraries: [library],
      auto_install: :never,
      generated_dir: generated_dir,
      metadata_dir: metadata_dir,
      helper_paths: [],
      helper_pack_enabled: false,
      helper_allowlist: [],
      inline_enabled: false,
      strict: false,
      verbose: false,
      scan_paths: [],
      scan_exclude: [],
      introspector: [env: %{"PYTHONPATH" => pythonpath}],
      docs: [],
      runtime_client: Snakepit,
      ledger: [],
      coverage_report: [output_dir: report_dir]
    }

    original_registry_path = Application.get_env(:snakebridge, :registry_path)
    Application.put_env(:snakebridge, :registry_path, Path.join(tmp_dir, "registry.json"))

    on_exit(fn ->
      restore_app_env(:snakebridge, :registry_path, original_registry_path)
    end)

    File.cd!(tmp_dir, fn ->
      assert {:ok, []} = Pipeline.run(config)
    end)

    json_report = Path.join(report_dir, "fixture_runtime.coverage.json")
    md_report = Path.join(report_dir, "fixture_runtime.coverage.md")

    assert File.exists?(json_report)
    assert File.exists?(md_report)

    report = json_report |> File.read!() |> Jason.decode!()
    assert report["library"] == "fixture_runtime"
    assert report["summary"]["symbols_total"] > 0
  end

  @tag :tmp_dir
  test "generate: :all with submodules true discovers submodule functions", %{tmp_dir: tmp_dir} do
    TestHelpers.ensure_python!()

    fixtures_path = Path.expand("../fixtures/python", __DIR__)
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    pythonpath =
      [fixtures_path, System.get_env("PYTHONPATH")]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    library = %Library{
      name: :fixture_submodules,
      version: :stdlib,
      module_name: FixtureSubmodules,
      python_name: "fixture_submodules",
      generate: :all,
      submodules: true
    }

    generated_dir = Path.join(tmp_dir, "generated")
    metadata_dir = Path.join(tmp_dir, "metadata")

    config = %Config{
      libraries: [library],
      auto_install: :never,
      generated_dir: generated_dir,
      metadata_dir: metadata_dir,
      helper_paths: [],
      helper_pack_enabled: false,
      helper_allowlist: [],
      inline_enabled: false,
      strict: false,
      verbose: false,
      scan_paths: [],
      scan_exclude: [],
      introspector: [env: %{"PYTHONPATH" => pythonpath}],
      docs: [],
      runtime_client: Snakepit,
      ledger: []
    }

    original_registry_path = Application.get_env(:snakebridge, :registry_path)
    Application.put_env(:snakebridge, :registry_path, Path.join(tmp_dir, "registry.json"))

    on_exit(fn ->
      restore_app_env(:snakebridge, :registry_path, original_registry_path)
    end)

    File.cd!(tmp_dir, fn ->
      assert {:ok, []} = Pipeline.run(config)
    end)

    manifest_path = Path.join(metadata_dir, "manifest.json")
    manifest = manifest_path |> File.read!() |> Jason.decode!()

    assert Enum.any?(Map.values(manifest["symbols"]), fn info ->
             info["python_module"] == "fixture_submodules.submod" and info["name"] == "sub_func"
           end)
  end

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)
end
