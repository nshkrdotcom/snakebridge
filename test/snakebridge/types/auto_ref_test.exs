defmodule SnakeBridge.Types.AutoRefTest do
  use ExUnit.Case, async: true

  describe "Python auto-ref for unknown types" do
    test "pandas DataFrame returns ref not string" do
      # This test requires integration with real Python
      # For unit test, verify decoder handles ref structure
      ref_data = %{
        "__type__" => "ref",
        "__schema__" => 1,
        "id" => "abc123",
        "session_id" => "default",
        "python_module" => "pandas",
        "library" => "pandas"
      }

      result = SnakeBridge.Types.decode(ref_data)
      assert %SnakeBridge.Ref{} = result
    end
  end
end
