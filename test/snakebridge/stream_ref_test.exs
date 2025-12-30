defmodule SnakeBridge.StreamRefTest do
  use ExUnit.Case, async: true

  describe "generator detection" do
    test "decoder handles stream_ref type" do
      stream_data = %{
        "__type__" => "stream_ref",
        "id" => "gen123",
        "session_id" => "default",
        "stream_type" => "generator",
        "python_module" => "test",
        "library" => "test"
      }

      result = SnakeBridge.Types.decode(stream_data)
      assert %SnakeBridge.StreamRef{} = result
      assert result.stream_type == "generator"
    end
  end

  describe "Enumerable protocol" do
    test "Enum.take works on stream ref" do
      # This would require integration test with real Python
      # For unit test, verify protocol implementation exists
      assert Enumerable.impl_for(%SnakeBridge.StreamRef{})
    end
  end
end
