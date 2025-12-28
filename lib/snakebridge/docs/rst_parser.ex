defmodule SnakeBridge.Docs.RstParser do
  @moduledoc """
  Parses Python docstrings in various formats (Google, NumPy, Sphinx, Epytext).

  This module detects the docstring format and extracts structured information
  including parameters, return values, exceptions, and examples.

  ## Supported Formats

  - **Google style**: Uses `Args:`, `Returns:`, `Raises:` sections
  - **NumPy style**: Uses underlined section headers (`Parameters\n----------`)
  - **Sphinx/reST style**: Uses `:param:`, `:type:`, `:returns:` directives
  - **Epytext style**: Uses `@param`, `@type`, `@return` tags
  """

  @type parsed_doc :: %{
          short_description: String.t() | nil,
          long_description: String.t() | nil,
          params: [param()],
          returns: returns() | nil,
          raises: [raises()],
          examples: [String.t()],
          notes: String.t() | nil,
          style: atom()
        }

  @type param :: %{
          name: String.t(),
          type_name: String.t() | nil,
          description: String.t() | nil,
          optional: boolean(),
          default: String.t() | nil
        }

  @type returns :: %{
          type_name: String.t() | nil,
          description: String.t() | nil
        }

  @type raises :: %{
          type_name: String.t(),
          description: String.t() | nil
        }

  @doc """
  Parses a Python docstring and returns structured data.
  """
  @spec parse(String.t() | nil) :: parsed_doc()
  def parse(nil), do: empty_result()
  def parse(""), do: empty_result()

  def parse(docstring) when is_binary(docstring) do
    style = detect_style(docstring)
    lines = String.split(docstring, "\n")

    {short_desc, rest} = extract_short_description(lines)
    {long_desc, sections} = extract_long_description(rest)

    %{
      short_description: short_desc,
      long_description: long_desc,
      params: extract_params(sections, style),
      returns: extract_returns(sections, style),
      raises: extract_raises(sections, style),
      examples: extract_examples(sections, style),
      notes: extract_notes(sections, style),
      style: style
    }
  end

  @doc """
  Detects the docstring style based on content patterns.
  """
  @spec detect_style(String.t() | nil) :: atom()
  def detect_style(nil), do: :unknown
  def detect_style(""), do: :unknown

  def detect_style(docstring) do
    cond do
      epytext_style?(docstring) -> :epytext
      sphinx_style?(docstring) -> :sphinx
      numpy_style?(docstring) -> :numpy
      google_style?(docstring) -> :google
      true -> :unknown
    end
  end

  defp epytext_style?(docstring) do
    docstring =~ ~r/@param\s/ or docstring =~ ~r/@type\s/
  end

  defp sphinx_style?(docstring) do
    docstring =~ ~r/:param\s+\w+:/ or docstring =~ ~r/:returns:/
  end

  defp numpy_style?(docstring) do
    docstring =~ ~r/Parameters\n-+/ or docstring =~ ~r/Returns\n-+/
  end

  defp google_style?(docstring) do
    docstring =~ ~r/\n\s*Args:\s*\n/ or
      docstring =~ ~r/\n\s*Arguments:\s*\n/ or
      docstring =~ ~r/\n\s*Returns:\s*\n/ or
      docstring =~ ~r/\n\s*Raises:\s*\n/ or
      docstring =~ ~r/\n\s*Example:\s*\n/ or
      docstring =~ ~r/\n\s*Examples:\s*\n/
  end

  defp empty_result do
    %{
      short_description: nil,
      long_description: nil,
      params: [],
      returns: nil,
      raises: [],
      examples: [],
      notes: nil,
      style: :unknown
    }
  end

  defp extract_short_description([]), do: {nil, []}

  defp extract_short_description(lines) do
    # Skip leading empty lines
    lines = Enum.drop_while(lines, &(String.trim(&1) == ""))

    case lines do
      [] ->
        {nil, []}

      [first | rest] ->
        short = String.trim(first)

        if short == "" do
          {nil, rest}
        else
          {short, rest}
        end
    end
  end

  defp extract_long_description(lines) do
    # Skip empty lines after short description
    lines = Enum.drop_while(lines, &(String.trim(&1) == ""))

    # Find where sections start
    section_start = find_section_start(lines)

    case section_start do
      nil ->
        # No sections, all is long description
        long_desc =
          lines
          |> Enum.join("\n")
          |> String.trim()

        {(long_desc == "" && nil) || long_desc, []}

      index ->
        {desc_lines, section_lines} = Enum.split(lines, index)

        long_desc =
          desc_lines
          |> Enum.join("\n")
          |> String.trim()

        {(long_desc == "" && nil) || long_desc, section_lines}
    end
  end

  defp find_section_start(lines) do
    Enum.find_index(lines, fn line ->
      trimmed = String.trim(line)

      # Google style sections
      # NumPy style sections (check next line for dashes)
      # Sphinx style
      # Epytext style
      trimmed in [
        "Args:",
        "Arguments:",
        "Returns:",
        "Yields:",
        "Raises:",
        "Example:",
        "Examples:",
        "Note:",
        "Notes:",
        "Warning:",
        "Warnings:"
      ] or
        trimmed in [
          "Parameters",
          "Returns",
          "Yields",
          "Raises",
          "Examples",
          "Notes",
          "Warnings",
          "See Also",
          "References"
        ] or
        String.starts_with?(trimmed, ":param ") or
        String.starts_with?(trimmed, ":returns:") or
        String.starts_with?(trimmed, "@param ") or
        String.starts_with?(trimmed, "@return")
    end)
  end

  defp extract_params(sections, :google), do: extract_google_params(sections)
  defp extract_params(sections, :numpy), do: extract_numpy_params(sections)
  defp extract_params(sections, :sphinx), do: extract_sphinx_params(sections)
  defp extract_params(sections, :epytext), do: extract_epytext_params(sections)
  defp extract_params(_sections, _style), do: []

  defp extract_google_params(lines) do
    lines
    |> extract_section(["Args:", "Arguments:"])
    |> parse_google_items()
    |> Enum.map(&parse_google_param/1)
  end

  defp extract_numpy_params(lines) do
    lines
    |> extract_numpy_section("Parameters")
    |> parse_numpy_items()
    |> Enum.map(&parse_numpy_param/1)
  end

  defp extract_sphinx_params(lines) do
    lines
    |> Enum.filter(&String.starts_with?(String.trim(&1), ":param "))
    |> Enum.map(&parse_sphinx_param/1)
  end

  defp extract_epytext_params(lines) do
    lines
    |> Enum.filter(&String.starts_with?(String.trim(&1), "@param "))
    |> Enum.map(&parse_epytext_param/1)
  end

  defp parse_google_param({name_type, description}) do
    {name, type_name, optional, default} = parse_param_name_type(name_type)

    %{
      name: name,
      type_name: type_name,
      description: description,
      optional: optional,
      default: default
    }
  end

  defp parse_numpy_param({name_type, description}) do
    [name_part | type_parts] = String.split(name_type, " : ", parts: 2)
    name = String.trim(name_part)
    type_info = if type_parts != [], do: hd(type_parts), else: nil
    {type_name, optional} = parse_numpy_type(type_info)

    %{
      name: name,
      type_name: type_name,
      description: description,
      optional: optional,
      default: nil
    }
  end

  defp parse_sphinx_param(line) do
    case Regex.run(~r/:param\s+(\w+):\s*(.*)/, String.trim(line)) do
      [_, name, desc] ->
        %{name: name, type_name: nil, description: desc, optional: false, default: nil}

      _ ->
        %{name: "", type_name: nil, description: "", optional: false, default: nil}
    end
  end

  defp parse_epytext_param(line) do
    case Regex.run(~r/@param\s+(\w+):\s*(.*)/, String.trim(line)) do
      [_, name, desc] ->
        %{name: name, type_name: nil, description: desc, optional: false, default: nil}

      _ ->
        %{name: "", type_name: nil, description: "", optional: false, default: nil}
    end
  end

  defp parse_param_name_type(name_type) do
    # Pattern: "name (type, optional): description" or "name (type): description"
    case Regex.run(~r/^(\w+)\s*\(([^)]+)\)/, name_type) do
      [_, name, type_info] ->
        optional = String.contains?(type_info, "optional")
        type_name = type_info |> String.replace(~r/,?\s*optional/, "") |> String.trim()

        default =
          case Regex.run(~r/Defaults? to [`']?([^`']+)[`']?/, name_type) do
            [_, val] -> val
            _ -> nil
          end

        {name, type_name, optional, default}

      _ ->
        # Just name, no type
        name = name_type |> String.split() |> List.first() || ""
        {name, nil, false, nil}
    end
  end

  defp parse_numpy_type(nil), do: {nil, false}

  defp parse_numpy_type(type_info) do
    optional = String.contains?(type_info, "optional")
    type_name = type_info |> String.replace(~r/,?\s*optional/, "") |> String.trim()
    {type_name, optional}
  end

  defp extract_returns(sections, :google), do: extract_google_returns(sections)
  defp extract_returns(sections, :numpy), do: extract_numpy_returns(sections)
  defp extract_returns(sections, :sphinx), do: extract_sphinx_returns(sections)
  defp extract_returns(sections, :epytext), do: extract_epytext_returns(sections)
  defp extract_returns(_sections, _style), do: nil

  defp extract_google_returns(lines) do
    case extract_section(lines, ["Returns:", "Yields:"]) |> parse_google_items() do
      [] ->
        nil

      [{type_desc, description} | _] ->
        %{type_name: String.trim(type_desc), description: description}
    end
  end

  defp extract_numpy_returns(lines) do
    case extract_numpy_section(lines, "Returns") |> parse_numpy_items() do
      [] ->
        nil

      [{type_name, description} | _] ->
        %{type_name: type_name, description: description}
    end
  end

  defp extract_sphinx_returns(lines) do
    case Enum.find(lines, &String.contains?(&1, ":returns:")) do
      nil ->
        nil

      line ->
        case Regex.run(~r/:returns:\s*(.*)/, line) do
          [_, desc] -> %{type_name: nil, description: desc}
          _ -> nil
        end
    end
  end

  defp extract_epytext_returns(lines) do
    case Enum.find(lines, &String.contains?(&1, "@return")) do
      nil ->
        nil

      line ->
        case Regex.run(~r/@return\s*:?\s*(.*)/, line) do
          [_, desc] -> %{type_name: nil, description: desc}
          _ -> nil
        end
    end
  end

  defp extract_raises(sections, :google), do: extract_google_raises(sections)
  defp extract_raises(sections, :numpy), do: extract_numpy_raises(sections)
  defp extract_raises(sections, :sphinx), do: extract_sphinx_raises(sections)
  defp extract_raises(sections, :epytext), do: extract_epytext_raises(sections)
  defp extract_raises(_sections, _style), do: []

  defp extract_google_raises(lines) do
    lines
    |> extract_section(["Raises:"])
    |> parse_google_items()
    |> Enum.map(fn {type_name, description} ->
      %{type_name: String.trim(type_name), description: description}
    end)
  end

  defp extract_numpy_raises(lines) do
    lines
    |> extract_numpy_section("Raises")
    |> parse_numpy_items()
    |> Enum.map(fn {type_name, description} ->
      %{type_name: type_name, description: description}
    end)
  end

  defp extract_sphinx_raises(lines) do
    lines
    |> Enum.filter(&String.contains?(&1, ":raises"))
    |> Enum.map(fn line ->
      case Regex.run(~r/:raises?\s+(\w+):\s*(.*)/, line) do
        [_, type, desc] -> %{type_name: type, description: desc}
        _ -> %{type_name: "Error", description: ""}
      end
    end)
  end

  defp extract_epytext_raises(lines) do
    lines
    |> Enum.filter(&String.contains?(&1, "@raise"))
    |> Enum.map(fn line ->
      case Regex.run(~r/@raise\s+(\w+):\s*(.*)/, line) do
        [_, type, desc] -> %{type_name: type, description: desc}
        _ -> %{type_name: "Error", description: ""}
      end
    end)
  end

  defp extract_examples(sections, style) do
    section_content =
      case style do
        :google -> extract_section(sections, ["Example:", "Examples:"])
        :numpy -> extract_numpy_section(sections, "Examples")
        _ -> []
      end

    section_content
    |> Enum.join("\n")
    |> String.trim()
    |> case do
      "" -> []
      content -> [content]
    end
  end

  defp extract_notes(sections, style) do
    section_content =
      case style do
        :google -> extract_section(sections, ["Note:", "Notes:"])
        :numpy -> extract_numpy_section(sections, "Notes")
        _ -> []
      end

    section_content
    |> Enum.join("\n")
    |> String.trim()
    |> case do
      "" -> nil
      content -> content
    end
  end

  defp extract_section(lines, headers) do
    start_idx =
      Enum.find_index(lines, fn line ->
        String.trim(line) in headers
      end)

    case start_idx do
      nil -> []
      idx -> extract_section_content(lines, idx)
    end
  end

  defp extract_section_content(lines, idx) do
    lines
    |> Enum.drop(idx + 1)
    |> Enum.take_while(&line_in_section?/1)
  end

  defp line_in_section?(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> true
      section_header?(trimmed) -> false
      indented_line?(line) -> true
      true -> false
    end
  end

  defp indented_line?(line) do
    String.starts_with?(line, "    ") or String.starts_with?(line, "\t")
  end

  defp extract_numpy_section(lines, header) do
    start_idx =
      Enum.find_index(lines, fn line ->
        String.trim(line) == header
      end)

    case start_idx do
      nil -> []
      idx -> extract_numpy_section_content(lines, idx)
    end
  end

  defp extract_numpy_section_content(lines, idx) do
    lines
    |> Enum.drop(idx + 2)
    |> Enum.with_index(idx + 2)
    |> Enum.take_while(fn {line, line_idx} ->
      line_in_numpy_section?(lines, line, line_idx)
    end)
    |> Enum.map(fn {line, _idx} -> line end)
  end

  defp line_in_numpy_section?(lines, line, line_idx) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> true
      numpy_section_header?(lines, line_idx) -> false
      true -> true
    end
  end

  defp section_header?(line) do
    line in [
      "Args:",
      "Arguments:",
      "Returns:",
      "Yields:",
      "Raises:",
      "Example:",
      "Examples:",
      "Note:",
      "Notes:",
      "Warning:",
      "Warnings:"
    ]
  end

  defp numpy_section_header?(lines, idx) when is_integer(idx) and idx >= 0 do
    case Enum.at(lines, idx + 1) do
      nil -> false
      next_line -> String.trim(next_line) =~ ~r/^-+$/
    end
  end

  defp numpy_section_header?(_lines, _idx), do: false

  defp parse_google_items(lines) do
    lines
    |> Enum.chunk_while(nil, &google_chunk_reducer/2, &chunk_finalizer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&split_google_item/1)
  end

  defp google_chunk_reducer(line, acc) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        emit_chunk_on_empty(acc)

      google_item_header?(trimmed) ->
        emit_and_start_new_chunk(acc, trimmed)

      acc != nil ->
        {:cont, acc <> " " <> trimmed}

      true ->
        {:cont, nil}
    end
  end

  defp google_item_header?(trimmed) do
    String.match?(trimmed, ~r/^\w+(\s*\([^)]*\))?:/)
  end

  defp split_google_item(item) do
    case String.split(item, ":", parts: 2) do
      [name_type, desc] -> {String.trim(name_type), String.trim(desc)}
      [name_type] -> {String.trim(name_type), ""}
    end
  end

  defp parse_numpy_items(lines) do
    lines
    |> Enum.chunk_while(nil, &numpy_chunk_reducer/2, &chunk_finalizer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&split_numpy_item/1)
  end

  defp numpy_chunk_reducer(line, acc) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        emit_chunk_on_empty(acc)

      numpy_item_header?(line) ->
        emit_and_start_new_chunk(acc, line)

      acc != nil ->
        {:cont, acc <> " " <> trimmed}

      true ->
        {:cont, nil}
    end
  end

  defp numpy_item_header?(line) do
    String.contains?(line, " : ") or not String.starts_with?(line, " ")
  end

  defp split_numpy_item(item) do
    case String.split(item, "\n", parts: 2) do
      [first, rest] ->
        {String.trim(first), String.trim(rest)}

      [first] ->
        split_numpy_single_line(first)
    end
  end

  defp split_numpy_single_line(line) do
    case String.split(line, " : ", parts: 2) do
      [name, desc] -> {String.trim(name), String.trim(desc)}
      [name] -> {String.trim(name), ""}
    end
  end

  # Shared chunk helpers for both Google and NumPy parsers
  defp emit_chunk_on_empty(nil), do: {:cont, nil}
  defp emit_chunk_on_empty(acc), do: {:cont, acc, nil}

  defp emit_and_start_new_chunk(nil, new_value), do: {:cont, new_value}
  defp emit_and_start_new_chunk(acc, new_value), do: {:cont, acc, new_value}

  defp chunk_finalizer(nil), do: {:cont, []}
  defp chunk_finalizer(acc), do: {:cont, acc, []}
end
