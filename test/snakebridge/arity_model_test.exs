defmodule SnakeBridge.ArityModelTest do
  use ExUnit.Case, async: true

  describe "manifest arity range matching" do
    test "call-site arity 3 matches manifest required_arity 2 with optional params" do
      manifest = %{
        "symbols" => %{
          "Lib.func/2" => %{
            "required_arity" => 2,
            "minimum_arity" => 2,
            "maximum_arity" => 4,
            "has_var_positional" => false
          }
        }
      }

      # Call with 3 args should match function with min=2, max=4
      assert SnakeBridge.Manifest.call_supported?(manifest, Lib, :func, 3)
    end

    test "call-site arity 5 does not match manifest max_arity 4" do
      manifest = %{
        "symbols" => %{
          "Lib.func/2" => %{
            "required_arity" => 2,
            "minimum_arity" => 2,
            "maximum_arity" => 4
          }
        }
      }

      refute SnakeBridge.Manifest.call_supported?(manifest, Lib, :func, 5)
    end

    test "unbounded arity with var_positional accepts any call-site arity" do
      manifest = %{
        "symbols" => %{
          "Lib.func/1" => %{
            "required_arity" => 1,
            "minimum_arity" => 1,
            "maximum_arity" => :unbounded,
            "has_var_positional" => true
          }
        }
      }

      assert SnakeBridge.Manifest.call_supported?(manifest, Lib, :func, 100)
    end
  end
end
