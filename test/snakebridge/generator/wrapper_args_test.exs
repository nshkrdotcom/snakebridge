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

      {param_names, has_opts} = Generator.build_params(params)

      assert param_names == ["a"]
      assert has_opts == true, "opts should be enabled for defaulted params"
    end

    test "function with VAR_POSITIONAL enables opts" do
      # Python: def print(*values, sep=' ')
      params = [
        %{"name" => "values", "kind" => "VAR_POSITIONAL"},
        %{"name" => "sep", "kind" => "KEYWORD_ONLY", "default" => "' '"}
      ]

      {param_names, has_opts} = Generator.build_params(params)

      assert param_names == []
      assert has_opts == true
    end

    test "pure positional function still accepts opts for runtime flags" do
      # Python: def abs(x)
      # Even with no optional Python params, we need opts for idempotent/__runtime__
      params = [
        %{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"}
      ]

      {param_names, has_opts} = Generator.build_params(params)

      assert param_names == ["x"]
      # DESIGN DECISION: If Option A chosen, this should be true
      # If Option B chosen, this should be false
      assert has_opts == true, "runtime flags require opts access"
    end
  end

  describe "render_function/2 generates correct wrappers" do
    test "wrapper with defaulted params accepts keyword opts" do
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

      assert source =~ "def mean(a, opts \\\\ [])"
      assert source =~ "SnakeBridge.Runtime.call(__MODULE__, :mean, [a], opts)"
    end
  end
end
