defmodule SnakeBridge.Docs.ManifestBuilderTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Docs.ManifestBuilder

  test "builds full profile from inventory entries" do
    inventory = %{
      entries: [
        %{
          name: "examplelib",
          domain_role: "py:module",
          priority: 1,
          uri: "x",
          dispname: "examplelib"
        },
        %{
          name: "examplelib.config",
          domain_role: "py:module",
          priority: 1,
          uri: "x",
          dispname: "examplelib.config"
        },
        %{
          name: "examplelib.config.Config",
          domain_role: "py:class",
          priority: 1,
          uri: "x",
          dispname: "examplelib.config.Config"
        },
        %{
          name: "examplelib.config.load_config",
          domain_role: "py:function",
          priority: 1,
          uri: "x",
          dispname: "examplelib.config.load_config"
        },
        %{
          name: "examplelib.Client.generate",
          domain_role: "py:method",
          priority: 1,
          uri: "x",
          dispname: "examplelib.Client.generate"
        }
      ]
    }

    profile = ManifestBuilder.from_inventory(inventory, "examplelib")

    assert "examplelib.config" in profile["modules"]

    assert Enum.any?(profile["objects"], fn obj ->
             obj["name"] == "examplelib.config.Config" and obj["kind"] == "class"
           end)

    refute Enum.any?(profile["objects"], fn obj ->
             obj["name"] == "examplelib.Client.generate"
           end)
  end

  test "from_inventory drops class-member functions that look like modules" do
    inventory = %{
      entries: [
        %{
          name: "examplelib.config",
          domain_role: "py:module",
          priority: 1,
          uri: "x",
          dispname: "examplelib.config"
        },
        %{
          name: "examplelib.config.Config",
          domain_role: "py:class",
          priority: 1,
          uri: "x",
          dispname: "examplelib.config.Config"
        },
        %{
          name: "examplelib.config.Config.from_env",
          domain_role: "py:function",
          priority: 1,
          uri: "x",
          dispname: "examplelib.config.Config.from_env"
        }
      ]
    }

    profile = ManifestBuilder.from_inventory(inventory, "examplelib")

    refute "examplelib.config.Config" in profile["modules"]

    refute Enum.any?(profile["objects"], fn obj ->
             obj["name"] == "examplelib.config.Config.from_env" and obj["kind"] == "function"
           end)
  end

  test "summary profile filters full profile by HTML references" do
    full = %{
      "modules" => ["examplelib", "examplelib.config"],
      "objects" => [
        %{"name" => "examplelib.Client", "kind" => "class"},
        %{"name" => "examplelib.config.Config", "kind" => "class"}
      ]
    }

    html = "<div>See examplelib.config.Config for details.</div>"
    summary = ManifestBuilder.summary_from_html(full, html, "examplelib")

    assert Enum.map(summary["objects"], & &1["name"]) == ["examplelib.config.Config"]
    assert summary["modules"] == ["examplelib", "examplelib.config"]
  end

  test "extract_modules_from_html_nav derives Python module names from href paths" do
    html = """
    <nav>
      <a href="examplelib/beam_search/">beam_search</a>
      <a href="examplelib/v1/worker/gpu/">gpu</a>
      <a href="examplelib/my-module/">hyphenated</a>
      <a href="examplelib/config/CacheConfig/">class page</a>
      <a href="not_examplelib/ignore/">ignore</a>
    </nav>
    """

    modules = ManifestBuilder.extract_modules_from_html_nav(html, "examplelib")

    assert MapSet.member?(modules, "examplelib.beam_search")
    assert MapSet.member?(modules, "examplelib.v1.worker.gpu")
    assert MapSet.member?(modules, "examplelib.my_module")
    refute MapSet.member?(modules, "examplelib.config.CacheConfig")
    refute MapSet.member?(modules, "not_examplelib.ignore")
  end

  test "from_inventory includes allowlisted modules even when inventory lacks py:module entries" do
    inventory = %{
      entries: [
        %{
          name: "examplelib",
          domain_role: "py:module",
          priority: 1,
          uri: "x",
          dispname: "examplelib"
        }
      ]
    }

    profile =
      ManifestBuilder.from_inventory(inventory, "examplelib",
        module_allowlist: MapSet.new(["examplelib.beam_search"])
      )

    assert "examplelib" in profile["modules"]
    assert "examplelib.beam_search" in profile["modules"]
  end

  test "filter_modules_by_depth limits modules relative to root" do
    modules =
      MapSet.new([
        "examplelib",
        "examplelib.config",
        "examplelib.multimodal.inputs",
        "examplelib.v1.worker.gpu"
      ])

    filtered = ManifestBuilder.filter_modules_by_depth(modules, "examplelib", 1)

    assert MapSet.member?(filtered, "examplelib")
    assert MapSet.member?(filtered, "examplelib.config")
    refute MapSet.member?(filtered, "examplelib.multimodal.inputs")
    refute MapSet.member?(filtered, "examplelib.v1.worker.gpu")
  end

  test "merge_profiles unions modules and objects" do
    a = %{
      "modules" => ["examplelib", "examplelib.config"],
      "objects" => [%{"name" => "examplelib.Client", "kind" => "class"}]
    }

    b = %{
      "modules" => ["examplelib", "examplelib.inputs"],
      "objects" => [%{"name" => "examplelib.inputs.TextPrompt", "kind" => "class"}]
    }

    merged = ManifestBuilder.merge_profiles(a, b)

    assert merged["modules"] == ["examplelib", "examplelib.config", "examplelib.inputs"]

    assert Enum.map(merged["objects"], & &1["name"]) ==
             ["examplelib.Client", "examplelib.inputs.TextPrompt"]
  end
end
