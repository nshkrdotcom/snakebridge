defmodule SnakeBridge.Docs.MarkdownSanitizer do
  @moduledoc false

  @manpage_quote_regex ~r/`([A-Za-z0-9_.:\/-]+)'/

  @spec sanitize(String.t() | nil) :: String.t()
  def sanitize(nil), do: ""

  def sanitize(markdown) when is_binary(markdown) do
    markdown
    |> fix_unclosed_fences()
    |> fix_manpage_quotes_outside_fences()
  end

  defp fix_unclosed_fences(markdown) do
    lines = String.split(markdown, "\n", trim: false)
    {in_fence, open_index, indent} = last_unclosed_fence(lines)

    if in_fence and not is_nil(open_index) do
      insert_at = find_fence_insertion(lines, open_index + 1)
      updated = List.insert_at(lines, insert_at, indent <> "```")
      Enum.join(updated, "\n")
    else
      markdown
    end
  end

  defp last_unclosed_fence(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce({false, nil, ""}, fn {line, idx}, acc ->
      toggle_fence_state(line, idx, acc)
    end)
  end

  defp toggle_fence_state(line, idx, {in_fence, open_index, indent}) do
    case {fence_line?(line), in_fence} do
      {true, true} -> {false, nil, ""}
      {true, false} -> {true, idx, leading_indent(line)}
      {false, _} -> {in_fence, open_index, indent}
    end
  end

  defp find_fence_insertion(lines, start_index) do
    max_index = length(lines) - 1

    if start_index > max_index do
      length(lines)
    else
      find_insertion_point(lines, start_index, max_index)
    end
  end

  defp find_insertion_point(lines, start_index, max_index) do
    blank_boundary = find_blank_boundary(lines, start_index, max_index)

    if is_integer(blank_boundary) do
      blank_boundary
    else
      find_prose_fallback(lines, start_index, max_index)
    end
  end

  defp find_blank_boundary(lines, start_index, max_index) do
    Enum.find(start_index..max_index, fn idx ->
      line = Enum.at(lines, idx)
      next_line = if idx + 1 <= max_index, do: Enum.at(lines, idx + 1), else: nil

      String.trim(line) == "" and not is_nil(next_line) and prose_like?(next_line)
    end)
  end

  defp find_prose_fallback(lines, start_index, max_index) do
    fallback =
      Enum.find(start_index..max_index, fn idx ->
        prose_like?(Enum.at(lines, idx))
      end)

    fallback || length(lines)
  end

  defp prose_like?(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> false
      String.starts_with?(trimmed, "## ") -> true
      String.starts_with?(trimmed, ["#", "-", "*", ">", "|"]) -> false
      true -> looks_like_prose?(trimmed)
    end
  end

  defp looks_like_prose?(trimmed) do
    has_space = String.contains?(trimmed, " ")
    code_like = code_like?(trimmed)

    has_space and not code_like and prose_structure?(trimmed)
  end

  defp prose_structure?(trimmed) do
    sentence_case = Regex.match?(~r/^[A-Z][a-z]/, trimmed)
    ends_with_punct = Regex.match?(~r/[.!?]$/, trimmed)

    sentence_case or ends_with_punct
  end

  defp code_like?(trimmed) do
    Regex.match?(~r/^\w+\(/, trimmed) or
      String.contains?(trimmed, " = ") or
      String.contains?(trimmed, "==") or
      String.contains?(trimmed, "->")
  end

  defp fix_manpage_quotes_outside_fences(markdown) do
    markdown
    |> String.split("\n", trim: false)
    |> replace_quotes(false, [])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp replace_quotes([], _in_fence, acc), do: acc

  defp replace_quotes([line | rest], in_fence, acc) do
    if fence_line?(line) do
      replace_quotes(rest, not in_fence, [line | acc])
    else
      updated =
        if in_fence do
          line
        else
          Regex.replace(@manpage_quote_regex, line, "`\\1`")
        end

      replace_quotes(rest, in_fence, [updated | acc])
    end
  end

  defp fence_line?(line) do
    line
    |> String.trim_leading()
    |> String.starts_with?("```")
  end

  defp leading_indent(line) do
    case Regex.run(~r/^\s*/, line) do
      [indent] -> indent
      _ -> ""
    end
  end
end
