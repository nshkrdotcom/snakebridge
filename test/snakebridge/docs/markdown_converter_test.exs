defmodule SnakeBridge.Docs.MarkdownConverterTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Docs.MarkdownConverter

  describe "convert/1" do
    test "converts short description" do
      parsed = %{
        short_description: "Calculate the sum of values.",
        long_description: nil,
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~ "Calculate the sum of values."
    end

    test "converts long description" do
      parsed = %{
        short_description: "Summary.",
        long_description: "Extended description with details.",
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~ "Extended description with details."
    end

    test "converts parameters to markdown list" do
      parsed = %{
        short_description: "Summary.",
        long_description: nil,
        params: [
          %{name: "x", type_name: "int", description: "The x value."},
          %{name: "y", type_name: "float", description: "The y value."}
        ],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~ "## Parameters"
      assert result =~ "`x`"
      assert result =~ "The x value"
      assert result =~ "`integer()`" or result =~ "int"
    end

    test "converts returns section" do
      parsed = %{
        short_description: "Summary.",
        long_description: nil,
        params: [],
        returns: %{type_name: "bool", description: "True if successful."},
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~ "## Returns"
      assert result =~ "True if successful"
    end

    test "converts raises section" do
      parsed = %{
        short_description: "Summary.",
        long_description: nil,
        params: [],
        returns: nil,
        raises: [
          %{type_name: "ValueError", description: "If value is invalid."},
          %{type_name: "TypeError", description: "If type is wrong."}
        ],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~ "## Raises"
      assert result =~ "ValueError" or result =~ "ArgumentError"
      assert result =~ "If value is invalid"
    end

    test "converts examples with iex prefix" do
      parsed = %{
        short_description: "Summary.",
        long_description: nil,
        params: [],
        returns: nil,
        raises: [],
        examples: [">>> func(1, 2)\n3"]
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~ "## Examples"
      assert result =~ "iex>" or result =~ ">>>"
    end

    test "handles empty parsed struct" do
      parsed = %{
        short_description: nil,
        long_description: nil,
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert is_binary(result)
    end

    test "wraps grid tables in code fences" do
      table = "+---+---+\n| a | b |\n+---+---+"

      parsed = %{
        short_description: "Summary.",
        long_description: table,
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~ "```\n+---+---+\n| a | b |\n+---+---+\n```"
    end

    test "sanitizes manpage-style backticks" do
      parsed = %{
        short_description: "Use `sys.byteorder' as the byte order value.",
        long_description: nil,
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~ "`sys.byteorder`"
      refute result =~ "`sys.byteorder'"
    end

    test "does not alter inline code with apostrophes" do
      parsed = %{
        short_description:
          "Consider using `dspy.LM(model='gpt-5', temperature=1.0, max_tokens=32000)` for optimal performance.",
        long_description: nil,
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert result =~
               "`dspy.LM(model='gpt-5', temperature=1.0, max_tokens=32000)`"
    end

    test "closes unclosed fences before prose" do
      parsed = %{
        short_description: nil,
        long_description: "capture as:\n\n```python\nx = 1\n\nIn the end, sizes are updated.\n",
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)
      [before, _after] = String.split(result, "In the end", parts: 2)

      assert String.trim_trailing(before) |> String.ends_with?("```")
    end

    test "does not alter balanced fences" do
      parsed = %{
        short_description: nil,
        long_description: "```python\nx = 1\n```\nDone",
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)

      assert length(Regex.scan(~r/^```/m, result)) == 2
    end

    test "sanitizes links after closing unclosed fences" do
      parsed = %{
        short_description: nil,
        long_description: "```python\nx = 1\n\nOutside [bad](../x)",
        params: [],
        returns: nil,
        raises: [],
        examples: []
      }

      result = MarkdownConverter.convert(parsed)
      [before, _after] = String.split(result, "Outside", parts: 2)

      assert String.trim_trailing(before) |> String.ends_with?("```")
      assert result =~ "Outside bad"
      refute result =~ "(../x)"
    end
  end

  describe "convert_type/1" do
    test "converts Python int to Elixir integer()" do
      assert MarkdownConverter.convert_type("int") == "integer()"
    end

    test "converts Python float to Elixir float()" do
      assert MarkdownConverter.convert_type("float") == "float()"
    end

    test "converts Python str to Elixir String.t()" do
      assert MarkdownConverter.convert_type("str") == "String.t()"
    end

    test "converts Python bool to Elixir boolean()" do
      assert MarkdownConverter.convert_type("bool") == "boolean()"
    end

    test "converts Python None to nil" do
      assert MarkdownConverter.convert_type("None") == "nil"
    end

    test "converts Python list to Elixir list()" do
      assert MarkdownConverter.convert_type("list") == "list()"
    end

    test "converts Python dict to Elixir map()" do
      assert MarkdownConverter.convert_type("dict") == "map()"
    end

    test "handles list[int]" do
      assert MarkdownConverter.convert_type("list[int]") == "list(integer())"
    end

    test "handles Optional[str]" do
      result = MarkdownConverter.convert_type("Optional[str]")
      assert result =~ "nil" or result =~ "String.t()"
    end

    test "returns original for unknown types" do
      assert MarkdownConverter.convert_type("CustomClass") == "CustomClass"
    end

    test "handles nil" do
      assert MarkdownConverter.convert_type(nil) == "term()"
    end
  end

  describe "convert_exception/1" do
    test "converts ValueError to ArgumentError" do
      assert MarkdownConverter.convert_exception("ValueError") == "ArgumentError"
    end

    test "converts TypeError to ArgumentError" do
      assert MarkdownConverter.convert_exception("TypeError") == "ArgumentError"
    end

    test "converts KeyError to KeyError" do
      assert MarkdownConverter.convert_exception("KeyError") == "KeyError"
    end

    test "converts RuntimeError to RuntimeError" do
      assert MarkdownConverter.convert_exception("RuntimeError") == "RuntimeError"
    end

    test "returns original for unknown exceptions" do
      assert MarkdownConverter.convert_exception("CustomError") == "CustomError"
    end
  end

  describe "convert_example/1" do
    test "converts Python >>> to Elixir iex>" do
      example = ">>> func(1, 2)\n3"

      result = MarkdownConverter.convert_example(example)

      assert result =~ "iex> func(1, 2)"
    end

    test "converts Python ... to Elixir ...>" do
      example = ">>> func(\n...     1, 2)"

      result = MarkdownConverter.convert_example(example)

      assert result =~ "...>"
    end

    test "preserves output lines" do
      example = ">>> func()\noutput"

      result = MarkdownConverter.convert_example(example)

      assert result =~ "output"
    end
  end
end
