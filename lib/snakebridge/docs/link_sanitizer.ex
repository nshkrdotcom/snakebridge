defmodule SnakeBridge.Docs.LinkSanitizer do
  @moduledoc false

  @scheme_regex ~r/^[a-z][a-z0-9+.-]*:/i

  @spec sanitize(String.t() | nil) :: String.t()
  def sanitize(nil), do: ""

  def sanitize(markdown) when is_binary(markdown) do
    markdown
    |> String.split("\n", trim: false)
    |> sanitize_lines(false, [])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp sanitize_lines([], _in_fence, acc), do: acc

  defp sanitize_lines([line | rest], in_fence, acc) do
    if fence_line?(line) do
      sanitize_lines(rest, not in_fence, [line | acc])
    else
      sanitized = if in_fence, do: line, else: sanitize_inline_links(line)
      sanitize_lines(rest, in_fence, [sanitized | acc])
    end
  end

  defp fence_line?(line) do
    line
    |> String.trim_leading()
    |> String.starts_with?("```")
  end

  defp sanitize_inline_links(line) do
    line
    |> do_sanitize([])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp do_sanitize(<<"![" <> rest>>, acc) do
    case parse_link(rest, true) do
      {:ok, replacement, remainder} -> do_sanitize(remainder, [replacement | acc])
      :error -> do_sanitize(rest, ["![" | acc])
    end
  end

  defp do_sanitize(<<"[" <> rest>>, acc) do
    case parse_link(rest, false) do
      {:ok, replacement, remainder} -> do_sanitize(remainder, [replacement | acc])
      :error -> do_sanitize(rest, ["[" | acc])
    end
  end

  defp do_sanitize(<<char::utf8, rest::binary>>, acc) do
    do_sanitize(rest, [<<char::utf8>> | acc])
  end

  defp do_sanitize(<<>>, acc), do: acc

  defp parse_link(rest, is_image) do
    with {:ok, label, after_label} <- split_label(rest, []),
         {:ok, target, remainder} <- parse_target(after_label) do
      replacement =
        if unsafe_target?(target) do
          label
        else
          prefix = if is_image, do: "![", else: "["
          prefix <> label <> "](" <> target <> ")"
        end

      {:ok, replacement, remainder}
    else
      _ -> :error
    end
  end

  defp split_label(<<"]" <> rest>>, acc),
    do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp split_label(<<>>, _acc), do: :error

  defp split_label(<<char::utf8, rest::binary>>, acc) do
    split_label(rest, [<<char::utf8>> | acc])
  end

  defp parse_target(<<"(" <> rest>>) do
    case extract_parenthesized(rest, 1, []) do
      {:ok, target, remainder} -> {:ok, target, remainder}
      :error -> :error
    end
  end

  defp parse_target(_rest), do: :error

  defp extract_parenthesized(<<")" <> rest>>, 1, acc) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp extract_parenthesized(<<")" <> rest>>, depth, acc) do
    extract_parenthesized(rest, depth - 1, [")" | acc])
  end

  defp extract_parenthesized(<<"(" <> rest>>, depth, acc) do
    extract_parenthesized(rest, depth + 1, ["(" | acc])
  end

  defp extract_parenthesized(<<char::utf8, rest::binary>>, depth, acc) do
    extract_parenthesized(rest, depth, [<<char::utf8>> | acc])
  end

  defp extract_parenthesized(<<>>, _depth, _acc), do: :error

  defp unsafe_target?(target) do
    trimmed = String.trim(target)

    cond do
      trimmed == "" -> false
      String.starts_with?(trimmed, "#") -> false
      Regex.match?(@scheme_regex, trimmed) -> false
      true -> has_parent_traversal?(trimmed)
    end
  end

  defp has_parent_traversal?(target) do
    String.starts_with?(target, "../") or
      String.starts_with?(target, "..\\") or
      String.contains?(target, "/../") or
      String.contains?(target, "\\..\\")
  end
end
