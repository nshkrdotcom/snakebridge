defmodule SnakeBridge.Docs.MarkdownConverter do
  @moduledoc """
  Converts parsed Python docstrings to Elixir ExDoc Markdown format.

  This module transforms structured docstring data into Markdown that
  is compatible with ExDoc and follows Elixir documentation conventions.
  """

  alias SnakeBridge.Docs.LinkSanitizer
  alias SnakeBridge.Docs.MarkdownSanitizer
  alias SnakeBridge.Docs.MathRenderer

  @type_map %{
    "int" => "integer()",
    "float" => "float()",
    "str" => "String.t()",
    "string" => "String.t()",
    "bool" => "boolean()",
    "boolean" => "boolean()",
    "None" => "nil",
    "NoneType" => "nil",
    "list" => "list()",
    "dict" => "map()",
    "tuple" => "tuple()",
    "set" => "MapSet.t()",
    "bytes" => "binary()",
    "bytearray" => "binary()",
    "Any" => "term()",
    "object" => "term()"
  }

  @exception_map %{
    "ValueError" => "ArgumentError",
    "TypeError" => "ArgumentError",
    "KeyError" => "KeyError",
    "IndexError" => "Enum.OutOfBoundsError",
    "RuntimeError" => "RuntimeError",
    "NotImplementedError" => "RuntimeError",
    "IOError" => "File.Error",
    "OSError" => "File.Error",
    "FileNotFoundError" => "File.Error",
    "AttributeError" => "KeyError",
    "NameError" => "UndefinedFunctionError"
  }

  # Section builders - each returns nil if the section should be skipped
  @section_builders [
    :short_description,
    :long_description,
    :params,
    :returns,
    :raises,
    :examples,
    :notes
  ]

  @doc """
  Converts a parsed docstring structure to ExDoc Markdown format.

  ## Parameters

  - `parsed` - A map with keys: `:short_description`, `:long_description`,
    `:params`, `:returns`, `:raises`, `:examples`

  ## Returns

  A Markdown string suitable for use in `@doc` or `@moduledoc`.
  """
  @spec convert(map()) :: String.t()
  def convert(parsed) when is_map(parsed) do
    @section_builders
    |> Enum.map(&build_section(&1, parsed))
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> wrap_grid_tables()
    |> MathRenderer.render()
    |> MarkdownSanitizer.sanitize()
    |> LinkSanitizer.sanitize()
    |> String.trim()
  end

  defp build_section(:short_description, parsed), do: parsed[:short_description]
  defp build_section(:long_description, parsed), do: parsed[:long_description]

  defp build_section(:params, %{params: params}) when is_list(params) and params != [] do
    format_parameters(params)
  end

  defp build_section(:params, _parsed), do: nil

  defp build_section(:returns, %{returns: returns}) when not is_nil(returns) do
    format_returns(returns)
  end

  defp build_section(:returns, _parsed), do: nil

  defp build_section(:raises, %{raises: raises}) when is_list(raises) and raises != [] do
    format_raises(raises)
  end

  defp build_section(:raises, _parsed), do: nil

  defp build_section(:examples, %{examples: examples})
       when is_list(examples) and examples != [] do
    format_examples(examples)
  end

  defp build_section(:examples, _parsed), do: nil

  defp build_section(:notes, %{notes: notes}) when not is_nil(notes) do
    "## Notes\n\n#{notes}"
  end

  defp build_section(:notes, _parsed), do: nil

  defp wrap_grid_tables(text) when is_binary(text) do
    lines = String.split(text, "\n", trim: false)

    {out, table_lines, in_table, indent} =
      Enum.reduce(lines, {[], [], false, ""}, &process_grid_table_line/2)

    out = finalize_grid_table(out, table_lines, in_table, indent)

    Enum.join(out, "\n")
  end

  defp process_grid_table_line(line, {out, table_lines, in_table, indent}) do
    if grid_table_line?(line) do
      indent = if in_table, do: indent, else: leading_indent(line)
      {out, table_lines ++ [line], true, indent}
    else
      end_table_block(out, table_lines, in_table, indent, line)
    end
  end

  defp end_table_block(out, table_lines, true, indent, line) do
    {out ++ emit_table_block(table_lines, indent) ++ [line], [], false, ""}
  end

  defp end_table_block(out, _table_lines, false, _indent, line) do
    {out ++ [line], [], false, ""}
  end

  defp finalize_grid_table(out, table_lines, true, indent) do
    out ++ emit_table_block(table_lines, indent)
  end

  defp finalize_grid_table(out, _table_lines, false, _indent) do
    out
  end

  defp emit_table_block(lines, indent) do
    if grid_table_block?(lines) do
      fence = indent <> "```"
      [fence | lines] ++ [fence]
    else
      lines
    end
  end

  defp grid_table_block?(lines) do
    Enum.any?(lines, &grid_table_border?/1) and Enum.any?(lines, &grid_table_row?/1)
  end

  defp grid_table_line?(line) do
    grid_table_border?(line) or grid_table_row?(line)
  end

  defp grid_table_border?(line) do
    trimmed = String.trim(line)

    String.starts_with?(trimmed, "+") and String.ends_with?(trimmed, "+") and
      (String.contains?(trimmed, "-") or String.contains?(trimmed, "="))
  end

  defp grid_table_row?(line) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, "|") and String.ends_with?(trimmed, "|")
  end

  defp leading_indent(line) do
    case Regex.run(~r/^\s*/, line) do
      [indent] -> indent
      _ -> ""
    end
  end

  # Generic type patterns with their prefixes and converters
  # Format: {prefix, prefix_length, converter_function}
  @generic_type_patterns [
    {"Optional[", 9, :convert_optional},
    {"Union[", 6, :convert_union},
    {"list[", 5, :convert_list},
    {"List[", 5, :convert_list},
    {"dict[", 5, :convert_dict},
    {"Dict[", 5, :convert_dict},
    {"tuple[", 6, :convert_tuple},
    {"Tuple[", 6, :convert_tuple},
    {"set[", 4, :convert_set},
    {"Set[", 4, :convert_set}
  ]

  @doc """
  Converts a Python type annotation to an Elixir typespec format.

  ## Examples

      iex> MarkdownConverter.convert_type("int")
      "integer()"

      iex> MarkdownConverter.convert_type("list[str]")
      "list(String.t())"

  """
  @spec convert_type(String.t() | nil) :: String.t()
  def convert_type(nil), do: "term()"
  def convert_type(""), do: "term()"

  def convert_type(python_type) do
    python_type = String.trim(python_type)

    case Map.fetch(@type_map, python_type) do
      {:ok, elixir_type} -> elixir_type
      :error -> convert_generic_type(python_type)
    end
  end

  defp convert_generic_type(python_type) do
    @generic_type_patterns
    |> Enum.find_value(fn {prefix, prefix_len, converter} ->
      if String.starts_with?(python_type, prefix) do
        inner = extract_inner_type(python_type, prefix_len)
        apply_type_converter(converter, inner)
      end
    end)
    |> Kernel.||(python_type)
  end

  defp extract_inner_type(type_string, prefix_length) do
    String.slice(type_string, prefix_length..-2//1)
  end

  defp apply_type_converter(:convert_optional, inner) do
    "#{convert_type(inner)} | nil"
  end

  defp apply_type_converter(:convert_union, inner) do
    inner
    |> String.split(",")
    |> Enum.map_join(" | ", &(&1 |> String.trim() |> convert_type()))
  end

  defp apply_type_converter(:convert_list, inner) do
    "list(#{convert_type(inner)})"
  end

  defp apply_type_converter(:convert_dict, _inner) do
    "map()"
  end

  defp apply_type_converter(:convert_tuple, _inner) do
    "tuple()"
  end

  defp apply_type_converter(:convert_set, inner) do
    "MapSet.t(#{convert_type(inner)})"
  end

  @doc """
  Converts a Python exception type to an Elixir exception module.

  ## Examples

      iex> MarkdownConverter.convert_exception("ValueError")
      "ArgumentError"

  """
  @spec convert_exception(String.t() | nil) :: String.t()
  def convert_exception(nil), do: "RuntimeError"
  def convert_exception(""), do: "RuntimeError"

  def convert_exception(python_exception) do
    Map.get(@exception_map, python_exception, python_exception)
  end

  @doc """
  Converts a Python doctest example to Elixir iex format.

  ## Examples

      iex> MarkdownConverter.convert_example(">>> func(1, 2)\\n3")
      "    iex> func(1, 2)\\n    3"

  """
  @spec convert_example(String.t()) :: String.t()
  def convert_example(example) do
    Enum.map_join(String.split(example, "\n"), "\n", fn line ->
      cond do
        String.starts_with?(String.trim(line), ">>>") ->
          code = line |> String.trim() |> String.slice(3..-1//1) |> String.trim()
          "    iex> #{code}"

        String.starts_with?(String.trim(line), "...") ->
          code = line |> String.trim() |> String.slice(3..-1//1) |> String.trim()
          "    ...> #{code}"

        String.trim(line) == "" ->
          ""

        true ->
          "    #{String.trim(line)}"
      end
    end)
  end

  defp format_parameters(params) do
    param_lines =
      Enum.map(params, fn param ->
        name = param[:name] || param.name
        type_name = param[:type_name]
        description = param[:description]

        type_str =
          if type_name do
            " (type: `#{convert_type(type_name)}`)"
          else
            ""
          end

        default_str =
          if param[:default] do
            " Defaults to `#{param.default}`."
          else
            ""
          end

        desc_str = if description, do: " - #{description}", else: ""

        "- `#{name}`#{desc_str}#{type_str}#{default_str}"
      end)

    "## Parameters\n\n#{Enum.join(param_lines, "\n")}"
  end

  defp format_returns(returns) do
    type_str =
      if returns[:type_name] do
        "Returns `#{convert_type(returns.type_name)}`."
      else
        ""
      end

    desc_str =
      if returns[:description] do
        " #{returns.description}"
      else
        ""
      end

    "## Returns\n\n#{type_str}#{desc_str}"
  end

  defp format_raises(raises) do
    raise_lines =
      Enum.map(raises, fn r ->
        type = convert_exception(r[:type_name] || r.type_name)
        desc = r[:description] || ""
        "- `#{type}` - #{desc}"
      end)

    "## Raises\n\n#{Enum.join(raise_lines, "\n")}"
  end

  defp format_examples(examples) do
    formatted = Enum.map_join(examples, "\n\n", &convert_example/1)

    "## Examples\n\n#{formatted}"
  end
end
