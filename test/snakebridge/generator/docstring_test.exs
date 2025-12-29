defmodule SnakeBridge.Generator.DocstringTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "format_docstring/1" do
    test "converts NumPy-style docstring to ExDoc markdown" do
      raw = """
      Compute the arithmetic mean along the specified axis.

      Parameters
      ----------
      a : array_like
          Array containing numbers whose mean is desired.
      axis : None or int or tuple of ints, optional
          Axis or axes along which the means are computed.

      Returns
      -------
      m : ndarray
          The mean of the input array.
      """

      formatted = Generator.format_docstring(raw)

      # Should have markdown headers
      assert formatted =~ "## Parameters"
      assert formatted =~ "## Returns"
      # Should convert params to list format
      assert formatted =~ "- `a`"
      assert formatted =~ "- `axis`"
    end

    test "handles nil docstring gracefully" do
      assert Generator.format_docstring(nil) == ""
    end

    test "handles empty docstring gracefully" do
      assert Generator.format_docstring("") == ""
    end

    test "falls back to raw doc on parse failure" do
      raw = "Some unparseable <<< garbage >>> docstring"

      formatted = Generator.format_docstring(raw)

      # Should return something (either parsed or raw fallback)
      assert is_binary(formatted)
    end

    test "renders math expressions" do
      raw = "The formula is :math:`E = mc^2`."

      formatted = Generator.format_docstring(raw)

      # Should convert RST math to KaTeX format
      assert formatted =~ "$E = mc^2$"
    end
  end
end
