defmodule SnakeBridge.Generator.WrapperArgsTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "build_params/1 with POSITIONAL_OR_KEYWORD defaults" do
    test "function with defaulted POSITIONAL_OR_KEYWORD params enables opts" do
      # Python: def mean(a, axis=None, dtype=None)
      params = [
        %{"name" => "a", "kind" => "POSITIONAL_OR_KEYWORD"},
        %{"name" => "axis", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "None"},
        %{"name" => "dtype", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "None"}
      ]

      plan = Generator.build_params(params)

      assert Enum.map(plan.required, & &1.name) == ["a"]
      assert plan.has_args == true, "extra args should be enabled for defaulted params"
      assert plan.has_opts == true, "opts should be enabled for defaulted params"
    end

    test "function with VAR_POSITIONAL enables opts" do
      # Python: def print(*values, sep=' ')
      params = [
        %{"name" => "values", "kind" => "VAR_POSITIONAL"},
        %{"name" => "sep", "kind" => "KEYWORD_ONLY", "default" => "' '"}
      ]

      plan = Generator.build_params(params)

      assert Enum.map(plan.required, & &1.name) == []
      assert plan.has_args == true
      assert plan.has_opts == true
    end

    test "pure positional function still accepts opts for runtime flags" do
      # Python: def abs(x)
      # Even with no optional Python params, we need opts for idempotent/__runtime__
      params = [
        %{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"}
      ]

      plan = Generator.build_params(params)

      assert Enum.map(plan.required, & &1.name) == ["x"]
      assert plan.has_args == false
      # DESIGN DECISION: If Option A chosen, this should be true
      # If Option B chosen, this should be false
      assert plan.has_opts == true, "runtime flags require opts access"
    end
  end

  describe "render_function/2 generates correct wrappers" do
    test "wrapper with defaulted params generates multiple arities" do
      info = %{
        "name" => "mean",
        "parameters" => [
          %{"name" => "a", "kind" => "POSITIONAL_OR_KEYWORD"},
          %{"name" => "axis", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "None"}
        ],
        "docstring" => "Compute the arithmetic mean."
      }

      library = %SnakeBridge.Config.Library{
        name: :numpy,
        python_name: "numpy",
        module_name: Numpy,
        streaming: []
      }

      source = Generator.render_function(info, library)

      # Should generate multiple arities instead of args list
      assert source =~ "def mean(a) do"
      assert source =~ "def mean(a, opts) when"
      assert source =~ "def mean(a, axis) do"
      assert source =~ "def mean(a, axis, opts) when"
      assert source =~ "SnakeBridge.Runtime.call(__MODULE__, :mean, [a], [])"
      assert source =~ "SnakeBridge.Runtime.call(__MODULE__, :mean, [a, axis], opts)"
    end
  end
end
