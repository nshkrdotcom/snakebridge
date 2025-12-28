defmodule SnakeBridge.Docs.MathRenderer do
  @moduledoc """
  Renders LaTeX math expressions for documentation.

  Converts reStructuredText math directives to Markdown-compatible
  math notation (KaTeX/MathJax style).

  ## Supported Formats

  - Inline math: ``:math:`E = mc^2` `` → `$E = mc^2$`
  - Display math: `.. math::` blocks → `$$...$$`
  """

  @doc """
  Renders math expressions in a docstring, converting RST math to Markdown.

  ## Examples

      iex> MathRenderer.render("The formula is :math:`E = mc^2`.")
      "The formula is $E = mc^2$."

  """
  @spec render(String.t() | nil) :: String.t() | nil
  def render(nil), do: nil
  def render(""), do: ""

  def render(text) when is_binary(text) do
    text
    |> render_inline_math()
    |> render_display_math()
  end

  @doc """
  Extracts all math expressions from text.

  Returns a list of math expression strings (without delimiters).
  """
  @spec extract_math(String.t() | nil) :: [String.t()]
  def extract_math(nil), do: []
  def extract_math(""), do: []

  def extract_math(text) do
    inline = extract_inline_math(text)
    display = extract_display_math(text)
    inline ++ display
  end

  @doc """
  Converts math expressions to KaTeX-compatible format.

  KaTeX uses `$...$` for inline and `$$...$$` for display math.
  """
  @spec to_katex(String.t() | nil) :: String.t() | nil
  def to_katex(nil), do: nil
  def to_katex(""), do: ""

  def to_katex(text) do
    # KaTeX format is the same as our render output
    render(text)
  end

  # Render inline math: :math:`expr` → $expr$
  defp render_inline_math(text) do
    Regex.replace(
      ~r/:math:`([^`]+)`/,
      text,
      "$\\1$"
    )
  end

  # Render display math blocks
  defp render_display_math(text) do
    # Pattern for RST math blocks:
    # .. math::
    #
    #    expression
    Regex.replace(
      ~r/\.\.\s*math::\s*\n\s*\n((?:\s+.+\n?)+)/,
      text,
      fn _, content ->
        expr =
          content
          |> String.trim()
          |> String.replace(~r/^\s+/m, "")

        "\n$$\n#{expr}\n$$\n"
      end
    )
  end

  # Extract inline math expressions
  defp extract_inline_math(text) do
    Regex.scan(~r/:math:`([^`]+)`/, text)
    |> Enum.map(fn [_, expr] -> expr end)
  end

  # Extract display math expressions
  defp extract_display_math(text) do
    Regex.scan(
      ~r/\.\.\s*math::\s*\n\s*\n((?:\s+.+\n?)+)/,
      text
    )
    |> Enum.map(fn [_, content] ->
      content
      |> String.trim()
      |> String.replace(~r/^\s+/m, "")
    end)
  end
end
