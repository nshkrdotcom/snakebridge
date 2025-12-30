defmodule SnakeBridge.KeywordOnlyTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "keyword-only parameter handling" do
    test "build_params identifies required keyword-only params" do
      params = [
        %{"name" => "a", "kind" => "POSITIONAL_OR_KEYWORD"},
        %{"name" => "b", "kind" => "KEYWORD_ONLY"},
        %{"name" => "c", "kind" => "KEYWORD_ONLY", "default" => "nil"}
      ]

      plan = Generator.build_params(params)

      assert plan.required_keyword_only == [%{"name" => "b", "kind" => "KEYWORD_ONLY"}]

      assert plan.optional_keyword_only == [
               %{"name" => "c", "kind" => "KEYWORD_ONLY", "default" => "nil"}
             ]
    end
  end
end
