defmodule SnakeBridge.Docs.RstParserTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Docs.RstParser

  describe "parse/1" do
    test "extracts short description" do
      docstring = """
      Short description of function.

      Extended description here.
      """

      result = RstParser.parse(docstring)

      assert result.short_description == "Short description of function."
    end

    test "extracts long description" do
      docstring = """
      Short description.

      This is the extended description.
      It can span multiple lines.
      """

      result = RstParser.parse(docstring)

      assert result.long_description =~ "extended description"
      assert result.long_description =~ "multiple lines"
    end

    test "extracts parameters from Google style" do
      docstring = """
      Function summary.

      Args:
          x (int): The x value.
          y (float): The y value.
      """

      result = RstParser.parse(docstring)

      assert length(result.params) == 2
      assert Enum.find(result.params, &(&1.name == "x"))
      assert Enum.find(result.params, &(&1.name == "y"))
    end

    test "extracts parameters from NumPy style" do
      docstring = """
      Function summary.

      Parameters
      ----------
      x : int
          The x value.
      y : float
          The y value.
      """

      result = RstParser.parse(docstring)

      assert length(result.params) == 2
    end

    test "extracts parameters from Sphinx style" do
      docstring = """
      Function summary.

      :param x: The x value.
      :type x: int
      :param y: The y value.
      :type y: float
      """

      result = RstParser.parse(docstring)

      assert length(result.params) == 2
    end

    test "extracts returns section" do
      docstring = """
      Function summary.

      Returns:
          bool: True if successful.
      """

      result = RstParser.parse(docstring)

      assert result.returns != nil
      assert result.returns.type_name == "bool"
    end

    test "extracts raises section" do
      docstring = """
      Function summary.

      Raises:
          ValueError: If invalid.
          TypeError: If wrong type.
      """

      result = RstParser.parse(docstring)

      assert length(result.raises) == 2
    end

    test "extracts examples" do
      docstring = """
      Function summary.

      Example:
          >>> func(1, 2)
          3
      """

      result = RstParser.parse(docstring)

      assert result.examples != []
      assert hd(result.examples) =~ "func(1, 2)"
    end

    test "handles empty docstring" do
      result = RstParser.parse("")

      assert result.short_description == nil
      assert result.long_description == nil
      assert result.params == []
    end

    test "handles nil docstring" do
      result = RstParser.parse(nil)

      assert result.short_description == nil
      assert result.params == []
    end
  end

  describe "detect_style/1" do
    test "detects Google style" do
      docstring = """
      Summary.

      Args:
          x (int): Value.
      """

      assert RstParser.detect_style(docstring) == :google
    end

    test "detects NumPy style" do
      docstring = """
      Summary.

      Parameters
      ----------
      x : int
          Value.
      """

      assert RstParser.detect_style(docstring) == :numpy
    end

    test "detects Sphinx style" do
      docstring = """
      Summary.

      :param x: Value.
      :type x: int
      """

      assert RstParser.detect_style(docstring) == :sphinx
    end

    test "detects Epytext style" do
      docstring = """
      Summary.

      @param x: Value.
      @type x: int
      """

      assert RstParser.detect_style(docstring) == :epytext
    end

    test "returns :unknown for plain text" do
      docstring = "Just a simple summary with no structured sections."

      assert RstParser.detect_style(docstring) == :unknown
    end
  end
end
