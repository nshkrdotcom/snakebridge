defmodule SnakeBridge.DocsManifestPipelineTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Compiler.Pipeline
  alias SnakeBridge.TestHelpers

  setup context do
    TestHelpers.skip_unless_python(context)

    fixtures_path = Path.expand("../fixtures/python", __DIR__)
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    original_pythonpath = System.get_env("PYTHONPATH")

    pythonpath =
      [fixtures_path, original_pythonpath]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(path_sep)

    System.put_env("PYTHONPATH", pythonpath)

    on_exit(fn ->
      if original_pythonpath in [nil, ""] do
        System.delete_env("PYTHONPATH")
      else
        System.put_env("PYTHONPATH", original_pythonpath)
      end
    end)

    :ok
  end

  test "generate: :all with module_mode: :docs uses docs manifest objects" do
    manifest_path = TestHelpers.tmp_path(".fixture_runtime.docs.json")

    File.write!(
      manifest_path,
      Jason.encode!(%{
        "version" => 1,
        "library" => "fixture_runtime",
        "profiles" => %{
          "full" => %{
            "modules" => ["fixture_runtime"],
            "objects" => [
              %{"name" => "fixture_runtime.add", "kind" => "function"},
              %{"name" => "fixture_runtime.Greeter", "kind" => "class"}
            ]
          }
        }
      })
    )

    library = %SnakeBridge.Config.Library{
      name: :fixture_runtime,
      python_name: "fixture_runtime",
      module_name: FixtureRuntime,
      generate: :all,
      module_mode: :docs,
      docs_manifest: manifest_path,
      docs_profile: "full"
    }

    updated = Pipeline.test_process_generate_all_library(%{}, library)

    assert Enum.any?(Map.values(Map.get(updated, "symbols", %{})), fn info ->
             info["python_module"] == "fixture_runtime" and info["python_name"] == "add"
           end)

    assert Enum.any?(Map.values(Map.get(updated, "classes", %{})), fn info ->
             info["python_module"] == "fixture_runtime" and info["class"] == "Greeter"
           end)
  end
end
