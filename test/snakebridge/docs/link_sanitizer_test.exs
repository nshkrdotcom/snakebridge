defmodule SnakeBridge.Docs.LinkSanitizerTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Docs.LinkSanitizer

  test "strips unsafe parent traversal links" do
    input = "See [`model_copy`](../concepts/models.md#model-copy)."

    assert LinkSanitizer.sanitize(input) == "See `model_copy`."
  end

  test "keeps safe scheme links" do
    input = "[Docs](https://docs.example.com/path)"

    assert LinkSanitizer.sanitize(input) == input
  end

  test "keeps anchor links" do
    input = "[JSON Parsing](#json-parsing)"

    assert LinkSanitizer.sanitize(input) == input
  end

  test "keeps safe relative links" do
    input = "[Docs](concepts/models.md)"

    assert LinkSanitizer.sanitize(input) == input
  end

  test "does not sanitize inside fenced code blocks" do
    input = "```\n[bad](../x)\n```\nOutside [ok](../y)"
    expected = "```\n[bad](../x)\n```\nOutside ok"

    assert LinkSanitizer.sanitize(input) == expected
  end

  test "strips unsafe image links to plain alt text" do
    input = "See ![diagram](../img.png)"

    assert LinkSanitizer.sanitize(input) == "See diagram"
  end
end
