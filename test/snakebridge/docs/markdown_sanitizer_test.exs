defmodule SnakeBridge.Docs.MarkdownSanitizerTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Docs.MarkdownSanitizer

  describe "sanitize/1" do
    test "handles nil and empty strings" do
      assert MarkdownSanitizer.sanitize(nil) == ""
      assert MarkdownSanitizer.sanitize("") == ""
    end

    test "normalizes reST symmetric double backticks outside code fences" do
      input = "A ``dspy.Signature`` class or string declaring inputs/outputs."
      expected = "A `dspy.Signature` class or string declaring inputs/outputs."

      assert MarkdownSanitizer.sanitize(input) == expected
    end

    test "normalizes asymmetric double-lead single-trail backticks" do
      input = "optimizer-authored code can make per ``forward`. ``None`` removes the limit."
      expected = "optimizer-authored code can make per `forward`. `None` removes the limit."

      assert MarkdownSanitizer.sanitize(input) == expected
    end

    test "normalizes asymmetric single-lead double-trail backticks" do
      input = "call `forward`` to run predictor."
      expected = "call `forward` to run predictor."

      assert MarkdownSanitizer.sanitize(input) == expected
    end

    test "does not modify code inside fenced blocks" do
      input = """
      Outside ``foo``.
      ```python
      def bar():
          # ``inside`` should not change
          return 42
      ```
      After ``baz``.
      """

      expected = """
      Outside `foo`.
      ```python
      def bar():
          # ``inside`` should not change
          return 42
      ```
      After `baz`.
      """

      assert MarkdownSanitizer.sanitize(input) == expected
    end

    test "replaces manpage style quotes outside fences" do
      input = "Refer to `my_func' for details."
      expected = "Refer to `my_func` for details."

      assert MarkdownSanitizer.sanitize(input) == expected
    end
  end
end
