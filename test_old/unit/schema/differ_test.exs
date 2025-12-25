defmodule SnakeBridge.Schema.DifferTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Schema.Differ
  alias SnakeBridge.TestFixtures

  describe "diff/2" do
    test "detects added classes" do
      old_schema = %{classes: %{}}
      new_schema = %{classes: %{"Predict" => TestFixtures.sample_class_descriptor()}}

      diff = Differ.diff(old_schema, new_schema)

      assert [{:added, ["classes", "Predict"], _descriptor}] = diff
    end

    test "detects removed classes" do
      old_schema = %{classes: %{"Predict" => TestFixtures.sample_class_descriptor()}}
      new_schema = %{classes: %{}}

      diff = Differ.diff(old_schema, new_schema)

      assert [{:removed, ["classes", "Predict"], _descriptor}] = diff
    end

    test "detects modified classes" do
      old_descriptor = TestFixtures.sample_class_descriptor()
      new_descriptor = %{old_descriptor | docstring: "Updated documentation"}

      old_schema = %{classes: %{"Predict" => old_descriptor}}
      new_schema = %{classes: %{"Predict" => new_descriptor}}

      diff = Differ.diff(old_schema, new_schema)

      assert [{:modified, ["classes", "Predict"], old_desc, new_desc}] = diff
      assert old_desc.docstring != new_desc.docstring
    end

    test "detects added methods in existing class" do
      old_descriptor = %{
        TestFixtures.sample_class_descriptor()
        | methods: []
      }

      new_descriptor = TestFixtures.sample_class_descriptor()

      old_schema = %{classes: %{"Predict" => old_descriptor}}
      new_schema = %{classes: %{"Predict" => new_descriptor}}

      diff = Differ.diff(old_schema, new_schema)

      assert [{:modified, ["classes", "Predict"], _old, _new}] = diff
    end

    test "returns empty diff for identical schemas" do
      schema = TestFixtures.sample_introspection_response()

      diff = Differ.diff(schema, schema)

      assert diff == []
    end

    test "detects multiple changes" do
      old_schema = %{
        classes: %{
          "Predict" => TestFixtures.sample_class_descriptor(),
          "OldClass" => %{name: "OldClass"}
        }
      }

      new_schema = %{
        classes: %{
          "Predict" => %{TestFixtures.sample_class_descriptor() | docstring: "Updated"},
          "NewClass" => %{name: "NewClass"}
        }
      }

      diff = Differ.diff(old_schema, new_schema)

      # modified Predict, removed OldClass, added NewClass
      assert length(diff) == 3
      assert Enum.any?(diff, &match?({:modified, _, _, _}, &1))
      assert Enum.any?(diff, &match?({:added, _, _}, &1))
      assert Enum.any?(diff, &match?({:removed, _, _}, &1))
    end
  end

  describe "diff_summary/1" do
    test "summarizes changes in human-readable format" do
      diff = [
        {:added, ["classes", "NewClass"], %{name: "NewClass"}},
        {:removed, ["classes", "OldClass"], %{name: "OldClass"}},
        {:modified, ["classes", "Predict"], %{}, %{}}
      ]

      summary = Differ.diff_summary(diff)

      assert String.contains?(summary, "Added: 1")
      assert String.contains?(summary, "Removed: 1")
      assert String.contains?(summary, "Modified: 1")
    end
  end
end
