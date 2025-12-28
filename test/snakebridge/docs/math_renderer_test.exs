defmodule SnakeBridge.Docs.MathRendererTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Docs.MathRenderer

  describe "render/1" do
    test "renders inline math" do
      input = "The formula is :math:`E = mc^2`."

      result = MathRenderer.render(input)

      assert result =~ "$E = mc^2$"
    end

    test "renders display math blocks" do
      input = """
      The equation is:

      .. math::

         \\int_0^\\infty e^{-x} dx = 1
      """

      result = MathRenderer.render(input)

      assert result =~ "$$"
      assert result =~ "\\int_0^\\infty"
    end

    test "preserves non-math content" do
      input = "This is plain text without any math."

      result = MathRenderer.render(input)

      assert result == "This is plain text without any math."
    end

    test "handles multiple inline math expressions" do
      input = "Given :math:`a = 1` and :math:`b = 2`, then :math:`a + b = 3`."

      result = MathRenderer.render(input)

      assert result =~ "$a = 1$"
      assert result =~ "$b = 2$"
      assert result =~ "$a + b = 3$"
    end

    test "handles LaTeX fractions" do
      input = "The fraction is :math:`\\frac{1}{2}`."

      result = MathRenderer.render(input)

      assert result =~ "$\\frac{1}{2}$"
    end

    test "handles Greek letters" do
      input = "The angle is :math:`\\alpha + \\beta = \\gamma`."

      result = MathRenderer.render(input)

      assert result =~ "$\\alpha + \\beta = \\gamma$"
    end

    test "handles subscripts and superscripts" do
      input = "Value is :math:`x_i^2`."

      result = MathRenderer.render(input)

      assert result =~ "$x_i^2$"
    end

    test "handles nil input" do
      assert MathRenderer.render(nil) == nil
    end

    test "handles empty string" do
      assert MathRenderer.render("") == ""
    end
  end

  describe "extract_math/1" do
    test "extracts inline math expressions" do
      input = "Formula :math:`a^2 + b^2 = c^2` is Pythagorean."

      expressions = MathRenderer.extract_math(input)

      assert length(expressions) == 1
      assert hd(expressions) == "a^2 + b^2 = c^2"
    end

    test "extracts block math expressions" do
      input = """
      Equation:

      .. math::

         f(x) = ax^2 + bx + c
      """

      expressions = MathRenderer.extract_math(input)

      assert length(expressions) == 1
      assert hd(expressions) =~ "f(x)"
    end

    test "returns empty list when no math" do
      input = "Plain text without math."

      expressions = MathRenderer.extract_math(input)

      assert expressions == []
    end
  end

  describe "to_katex/1" do
    test "converts math to KaTeX-compatible format" do
      input = "The sum is :math:`\\sum_{i=1}^n i`."

      result = MathRenderer.to_katex(input)

      # KaTeX uses $...$ for inline and $$...$$ for display
      assert result =~ "$\\sum_{i=1}^n i$"
    end
  end
end
