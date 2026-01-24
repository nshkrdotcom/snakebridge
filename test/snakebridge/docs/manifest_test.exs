defmodule SnakeBridge.Docs.ManifestTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Docs.Manifest

  test "loads selected profile and normalizes kinds" do
    dir = Path.join(System.tmp_dir!(), "snakebridge_docs_manifest_test")
    File.mkdir_p!(dir)
    path = Path.join(dir, "examplelib.docs.json")

    File.write!(
      path,
      Jason.encode!(%{
        "version" => 1,
        "library" => "examplelib",
        "profiles" => %{
          "summary" => %{
            "modules" => ["examplelib", "examplelib.config"],
            "objects" => [
              %{"name" => "examplelib.Client", "kind" => "class"},
              %{"name" => "examplelib.config.Config", "kind" => "class"},
              %{"name" => "examplelib.__version__", "kind" => "data"}
            ]
          }
        }
      })
    )

    assert {:ok, profile} =
             Manifest.load_profile(%{
               docs_manifest: path,
               docs_profile: "summary",
               python_name: "examplelib"
             })

    assert profile.modules == ["examplelib", "examplelib.config"]

    assert Enum.any?(profile.objects, fn obj ->
             obj.name == "examplelib.config.Config" and obj.kind == :class
           end)
  end

  test "rejects manifest for another library" do
    dir = Path.join(System.tmp_dir!(), "snakebridge_docs_manifest_test_mismatch")
    File.mkdir_p!(dir)
    path = Path.join(dir, "mismatch.docs.json")

    File.write!(
      path,
      Jason.encode!(%{
        "version" => 1,
        "library" => "otherlib",
        "profiles" => %{"full" => %{"modules" => [], "objects" => []}}
      })
    )

    assert {:error, {:manifest_library_mismatch, "otherlib", "examplelib"}} =
             Manifest.load_profile(%{docs_manifest: path, python_name: "examplelib"})
  end
end
