defmodule SnakeBridge.ClassResolutionTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.ModuleResolver

  describe "class vs submodule disambiguation" do
    test "detects class attribute on parent module" do
      assert {:ok, %{"is_class" => true}} =
               SnakeBridge.Introspector.introspect_attribute(:datetime, "date")
    end

    test "falls back to submodule when not a class" do
      assert {:ok, %{"is_class" => false, "is_module" => true}} =
               SnakeBridge.Introspector.introspect_attribute(:os, "path")
    end

    test "resolve_class_or_submodule returns correct type" do
      library = %{python_name: "datetime", module_name: DateTime}

      assert {:class, "date", "datetime"} =
               ModuleResolver.resolve_class_or_submodule(library, DateTime.Date)
    end
  end
end
