defmodule MathDemoTest do
  use ExUnit.Case

  describe "generated modules" do
    test "Math module is generated and has functions" do
      functions = Math.__functions__()
      assert is_list(functions)
      assert length(functions) > 0

      names = Enum.map(functions, fn {name, _, _, _} -> name end)
      assert :sqrt in names
      assert :sin in names
      assert :cos in names
    end

    test "Json module is generated and has functions" do
      functions = Json.__functions__()
      assert is_list(functions)

      names = Enum.map(functions, fn {name, _, _, _} -> name end)
      assert :dumps in names
      assert :loads in names
    end

    test "Json module has classes" do
      classes = Json.__classes__()
      assert is_list(classes)
      assert length(classes) > 0
    end

    test "search returns ranked results" do
      results = Math.__search__("sq")
      assert [%{name: :sqrt, summary: _summary, relevance: _relevance} | _] = results
    end
  end

  describe "MathDemo helpers" do
    test "generated_structure returns libraries" do
      {:ok, info} = MathDemo.generated_structure()
      assert is_list(info.libraries)
      assert "math" in info.libraries
      assert "json" in info.libraries
    end

    test "discover returns :ok" do
      assert :ok == MathDemo.discover()
    end
  end

  describe "MathDemo runtime" do
    defmodule RuntimeClientStub do
      def execute("snakebridge.call", %{"function" => "sqrt", "args" => [2]}, _opts),
        do: {:ok, 1.41421356237}

      def execute("snakebridge.call", %{"function" => "sin", "args" => [1.0]}, _opts),
        do: {:ok, 0.84}

      def execute("snakebridge.call", %{"function" => "cos", "args" => [0.0]}, _opts),
        do: {:ok, 1.0}

      def execute(_tool, _payload, _opts), do: {:error, :unexpected}

      def execute_stream(_tool, _payload, _cb, _opts), do: :ok
    end

    setup do
      original = Application.get_env(:snakebridge, :runtime_client)

      Application.put_env(:snakebridge, :runtime_client, RuntimeClientStub)

      on_exit(fn ->
        if original do
          Application.put_env(:snakebridge, :runtime_client, original)
        else
          Application.delete_env(:snakebridge, :runtime_client)
        end
      end)

      :ok
    end

    test "compute_sample returns runtime results" do
      assert {:ok, %{sqrt: sqrt, sin: sin, cos: cos}} = MathDemo.compute_sample()
      assert sqrt > 1.4
      assert sin > 0.8
      assert cos == 1.0
    end
  end
end
