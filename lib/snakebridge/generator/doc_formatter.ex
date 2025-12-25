defmodule SnakeBridge.Generator.DocFormatter do
  @moduledoc """
  Formats Python docstrings into Elixir documentation strings.

  This module converts Python docstrings (as parsed by the introspection script)
  into well-formatted Elixir `@moduledoc` and `@doc` strings that follow Elixir
  conventions.

  ## Features

  - Converts Python docstring format to Elixir Markdown format
  - Extracts parameter descriptions and return value documentation
  - Preserves code examples and formatting
  - Generates nice "## Parameters" and "## Returns" sections

  ## Examples

      iex> introspection = %{
      ...>   "module" => "mylib",
      ...>   "docstring" => %{
      ...>     "summary" => "A utility library",
      ...>     "description" => "This library provides various utilities."
      ...>   }
      ...> }
      iex> DocFormatter.module_doc(introspection)
      "A utility library\\n\\nThis library provides various utilities."

  """

  @doc """
  Generates a `@moduledoc` string from introspection data.

  ## Parameters

    * `introspection` - The module introspection map containing docstring information

  ## Returns

  A formatted string suitable for use as `@moduledoc` content.

  ## Examples

      iex> introspection = %{
      ...>   "module" => "json",
      ...>   "docstring" => %{
      ...>     "summary" => "JSON encoder and decoder.",
      ...>     "description" => "Provides functions for JSON encoding/decoding."
      ...>   }
      ...> }
      iex> DocFormatter.module_doc(introspection)
      "JSON encoder and decoder.\\n\\nProvides functions for JSON encoding/decoding."

  """
  @spec module_doc(map()) :: String.t()
  def module_doc(%{"docstring" => docstring} = introspection) when is_map(docstring) do
    module_name = Map.get(introspection, "module", "Python Module")

    parts = [
      format_summary_and_description(docstring),
      format_module_metadata(introspection)
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> default_if_empty("Python module: #{module_name}")
  end

  def module_doc(%{"module" => module_name}) do
    "Python module: #{module_name}"
  end

  def module_doc(_), do: "Python module"

  @doc """
  Generates a `@doc` string from function introspection data.

  ## Parameters

    * `func_info` - The function introspection map containing docstring and signature info

  ## Returns

  A formatted string suitable for use as `@doc` content.

  ## Examples

      iex> func_info = %{
      ...>   "name" => "add",
      ...>   "docstring" => %{
      ...>     "summary" => "Add two numbers.",
      ...>     "params" => [
      ...>       %{"name" => "a", "description" => "First number"},
      ...>       %{"name" => "b", "description" => "Second number"}
      ...>     ],
      ...>     "returns" => %{"description" => "Sum of a and b"}
      ...>   },
      ...>   "parameters" => [
      ...>     %{"name" => "a", "type" => %{"type" => "int"}},
      ...>     %{"name" => "b", "type" => %{"type" => "int"}}
      ...>   ]
      ...> }
      iex> doc = DocFormatter.function_doc(func_info)
      iex> doc =~ "Add two numbers."
      true

  """
  @spec function_doc(map()) :: String.t()
  def function_doc(%{"docstring" => docstring} = func_info) when is_map(docstring) do
    func_name = Map.get(func_info, "name", "function")

    parts = [
      format_summary_and_description(docstring),
      format_parameters(docstring, func_info),
      format_returns(docstring),
      format_raises(docstring),
      format_examples(docstring)
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> default_if_empty("Python function: #{func_name}")
  end

  def function_doc(%{"name" => name}) do
    "Python function: #{name}"
  end

  def function_doc(_), do: "Python function"

  # Private Functions

  @spec format_summary_and_description(map()) :: String.t() | nil
  defp format_summary_and_description(%{"summary" => summary, "description" => description}) do
    parts =
      [summary, description]
      |> Enum.map(&sanitize_text/1)
      |> Enum.reject(&nil_or_empty?/1)

    case parts do
      [] -> nil
      _ -> Enum.join(parts, "\n\n")
    end
  end

  defp format_summary_and_description(%{"summary" => summary}) when not is_nil(summary) do
    sanitize_text(summary)
  end

  defp format_summary_and_description(%{"description" => description})
       when not is_nil(description) do
    sanitize_text(description)
  end

  defp format_summary_and_description(%{"raw" => raw}) when not is_nil(raw) do
    sanitize_text(raw)
  end

  defp format_summary_and_description(_), do: nil

  @spec format_module_metadata(map()) :: String.t() | nil
  defp format_module_metadata(introspection) do
    metadata = []

    metadata =
      if version = introspection["module_version"] do
        ["**Version:** #{version}" | metadata]
      else
        metadata
      end

    metadata =
      if file = introspection["file"] do
        ["**Source:** `#{file}`" | metadata]
      else
        metadata
      end

    case metadata do
      [] -> nil
      items -> Enum.reverse(items) |> Enum.join("\n")
    end
  end

  @spec format_parameters(map(), map()) :: String.t() | nil
  defp format_parameters(docstring, func_info) do
    # Try to get parameter docs from the docstring
    param_docs = Map.get(docstring, "params", [])

    # Get parameter signatures from function info
    param_sigs = Map.get(func_info, "parameters", [])

    # Create a map of parameter names to descriptions
    param_doc_map =
      param_docs
      |> Enum.map(fn doc ->
        {doc["name"], sanitize_text(doc["description"])}
      end)
      |> Map.new()

    # Build parameter documentation
    param_items =
      param_sigs
      |> Enum.map(fn param ->
        name = param["name"]
        description = Map.get(param_doc_map, name, "")

        # Format optional parameters
        opt_marker = if Map.get(param, "default"), do: " (optional)", else: ""

        # Get type info if available
        type_info = format_param_type(param["type"])

        case {description, type_info} do
          {"", ""} -> "  * `#{name}`#{opt_marker}"
          {"", type} -> "  * `#{name}`#{opt_marker} - #{type}"
          {desc, ""} -> "  * `#{name}`#{opt_marker} - #{desc}"
          {desc, type} -> "  * `#{name}` (#{type})#{opt_marker} - #{desc}"
        end
      end)

    case param_items do
      [] -> nil
      items -> "## Parameters\n\n" <> Enum.join(items, "\n")
    end
  end

  @spec format_param_type(map() | nil) :: String.t()
  defp format_param_type(nil), do: ""
  defp format_param_type(%{"type" => "any"}), do: ""

  defp format_param_type(%{"type" => type}) when is_binary(type) do
    python_type_to_elixir(type)
  end

  defp format_param_type(_), do: ""

  # Map of Python types to their Elixir equivalents
  @python_to_elixir_types %{
    "int" => "integer",
    "str" => "string",
    "bool" => "boolean",
    "float" => "float",
    "list" => "list",
    "dict" => "map",
    "tuple" => "tuple",
    "set" => "set",
    "none" => "nil"
  }

  @spec python_type_to_elixir(String.t()) :: String.t()
  defp python_type_to_elixir(type) do
    Map.get(@python_to_elixir_types, type, type)
  end

  @spec format_returns(map()) :: String.t() | nil
  defp format_returns(%{"returns" => returns}) when is_map(returns) do
    description = returns["description"]
    type = returns["type"]

    parts = []

    parts =
      if type && type != "" do
        ["**Type:** `#{type}`" | parts]
      else
        parts
      end

    parts =
      if description && description != "" do
        [sanitize_text(description) | parts]
      else
        parts
      end

    case parts do
      [] -> nil
      items -> "## Returns\n\n" <> (Enum.reverse(items) |> Enum.join("\n\n"))
    end
  end

  defp format_returns(_), do: nil

  @spec format_raises(map()) :: String.t() | nil
  defp format_raises(%{"raises" => raises}) when is_list(raises) and length(raises) > 0 do
    items =
      raises
      |> Enum.map(fn exc ->
        exception = exc["exception"] || "Exception"
        description = sanitize_text(exc["description"] || "")

        if description != "" do
          "  * `#{exception}` - #{description}"
        else
          "  * `#{exception}`"
        end
      end)

    "## Raises\n\n" <> Enum.join(items, "\n")
  end

  defp format_raises(_), do: nil

  @spec format_examples(map()) :: String.t() | nil
  defp format_examples(%{"examples" => examples}) when is_binary(examples) and examples != "" do
    "## Examples\n\n#{sanitize_text(examples)}"
  end

  defp format_examples(_), do: nil

  @spec nil_or_empty?(String.t() | nil) :: boolean()
  defp nil_or_empty?(nil), do: true
  defp nil_or_empty?(""), do: true
  defp nil_or_empty?(_), do: false

  @spec default_if_empty(String.t(), String.t()) :: String.t()
  defp default_if_empty("", default), do: default
  defp default_if_empty(value, _default), do: value

  @spec sanitize_text(String.t() | nil) :: String.t() | nil
  defp sanitize_text(nil), do: nil

  defp sanitize_text(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> convert_rst_to_markdown()
    |> wrap_python_examples()
    |> escape_problematic_angle_brackets()
    |> escape_unbalanced_backticks()
  end

  # Convert RST-style formatting to Markdown
  @spec convert_rst_to_markdown(String.t()) :: String.t()
  defp convert_rst_to_markdown(text) do
    text
    # Convert RST inline code ``code`` to Markdown `code`
    |> convert_rst_inline_code()
    # Convert RST roles :role:`text` to just `text`
    |> convert_rst_roles()
    # Convert RST reference markers .. [n] to [n]:
    |> convert_rst_references()
  end

  # Wrap Python REPL examples in code fences to prevent markdown parsing issues
  # This handles cases like `float[10](` being interpreted as markdown links
  @spec wrap_python_examples(String.t()) :: String.t()
  defp wrap_python_examples(text) do
    lines = String.split(text, "\n")
    {result_lines, current_block, in_block} = wrap_python_examples_impl(lines, [], [], false)

    # Handle any remaining block
    result_lines =
      if in_block and current_block != [] do
        result_lines ++ ["```python"] ++ Enum.reverse(current_block) ++ ["```"]
      else
        result_lines ++ Enum.reverse(current_block)
      end

    Enum.join(result_lines, "\n")
  end

  defp wrap_python_examples_impl([], result, current_block, in_block) do
    {result, current_block, in_block}
  end

  defp wrap_python_examples_impl([line | rest], result, current_block, in_block) do
    cond do
      # Line starts with >>> (Python REPL prompt) - start or continue a block
      String.starts_with?(String.trim_leading(line), ">>>") ->
        if in_block do
          # Continue the block
          wrap_python_examples_impl(rest, result, [line | current_block], true)
        else
          # Start a new block
          wrap_python_examples_impl(rest, result, [line], true)
        end

      # Line starts with ... (Python continuation) - continue the block if in one
      String.starts_with?(String.trim_leading(line), "...") and in_block ->
        wrap_python_examples_impl(rest, result, [line | current_block], true)

      # In a block and line is not empty - could be output, continue block
      in_block and String.trim(line) != "" ->
        wrap_python_examples_impl(rest, result, [line | current_block], true)

      # In a block and line is empty - end the block
      in_block and String.trim(line) == "" ->
        # Close the block and add to result
        closed_block = ["```python"] ++ Enum.reverse(current_block) ++ ["```", ""]
        wrap_python_examples_impl(rest, result ++ closed_block, [], false)

      # Not in a block - just add the line
      true ->
        wrap_python_examples_impl(rest, result ++ [line], [], false)
    end
  end

  # Convert RST double-backtick inline code to Markdown single-backtick
  # ``code`` -> `code`
  @spec convert_rst_inline_code(String.t()) :: String.t()
  defp convert_rst_inline_code(text) do
    # Match ``...`` and convert to `...`
    # Allow for content that may span multiple lines or contain spaces
    # Use a more permissive pattern that matches any content between double backticks
    Regex.replace(~r/``((?:[^`]|`(?!`))+?)``/, text, "`\\1`")
  end

  # Convert RST roles like :func:`name`, :class:`name`, :ref:`text` to `name`
  @spec convert_rst_roles(String.t()) :: String.t()
  defp convert_rst_roles(text) do
    # Match :role:`text` patterns and extract just the text
    # Common roles: func, class, ref, meth, attr, mod, obj, data, const, exc
    Regex.replace(
      ~r/:(?:func|class|ref|meth|attr|mod|obj|data|const|exc|py:[\w]+):`([^`]+)`/,
      text,
      "`\\1`"
    )
  end

  # Convert RST reference markers like .. [1] to [1]:
  @spec convert_rst_references(String.t()) :: String.t()
  defp convert_rst_references(text) do
    # Match .. [n] at start of line and convert to [n]:
    Regex.replace(~r/^\.\.\s+\[(\d+)\]/m, text, "[\\1]:")
  end

  # Only escape angle brackets that would cause Earmark warnings
  # Preserve: <https://...>, <http://...>, >>>
  # Escape: <class '...'>, <BLANKLINE>, <module ...>, bare <word> patterns
  @spec escape_problematic_angle_brackets(String.t()) :: String.t()
  defp escape_problematic_angle_brackets(text) do
    # First, protect valid patterns by replacing with placeholders
    text
    # Protect autolinks <https://...> and <http://...>
    |> protect_autolinks()
    # Protect Python REPL prompts >>>
    |> String.replace(">>>", "\x00REPL_PROMPT\x00")
    # Now escape remaining problematic angle brackets
    |> escape_remaining_angle_brackets()
    # Restore protected patterns
    |> restore_autolinks()
    |> String.replace("\x00REPL_PROMPT\x00", ">>>")
  end

  # Protect autolinks by temporarily replacing them
  @spec protect_autolinks(String.t()) :: String.t()
  defp protect_autolinks(text) do
    # Match <https://...> or <http://...> autolinks
    Regex.replace(~r/<(https?:\/\/[^>]+)>/, text, "\x00AUTOLINK:\\1\x00")
  end

  # Restore autolinks from placeholders
  @spec restore_autolinks(String.t()) :: String.t()
  defp restore_autolinks(text) do
    Regex.replace(~r/\x00AUTOLINK:([^\x00]+)\x00/, text, "<\\1>")
  end

  # Escape remaining angle brackets that are problematic
  # These are typically RST artifacts like <class 'int'>, <BLANKLINE>, <ufunc>, etc.
  @spec escape_remaining_angle_brackets(String.t()) :: String.t()
  defp escape_remaining_angle_brackets(text) do
    # Escape angle brackets that look like RST/Python artifacts
    # Patterns to escape:
    # - <BLANKLINE>, <ALL_CAPS> - test artifacts
    # - <class 'name'>, <module 'name'>, etc. - Python type repr
    # - <ufunc>, <function>, <method>, etc. - Python object types

    # Escape common Python type reprs: <class '...'>, <module '...'>, <function ...>, etc.
    text =
      Regex.replace(
        ~r/<(class|module|function|method|ufunc|built-in\s+\w+)\s*[^>]*>/,
        text,
        fn match, _ ->
          match |> String.replace("<", "&lt;") |> String.replace(">", "&gt;")
        end
      )

    # Escape ALL_CAPS patterns and BLANKLINE
    text = Regex.replace(~r/<(BLANKLINE|[A-Z][A-Z_]+)>/, text, "&lt;\\1&gt;")

    # Escape simple <ufunc> etc
    Regex.replace(~r/<(ufunc)>/, text, "&lt;\\1&gt;")
  end

  # Escape any remaining unbalanced backticks to avoid Earmark warnings
  # After RST conversion, we should only have balanced `code` pairs
  # Any remaining unbalanced backticks need to be escaped
  @spec escape_unbalanced_backticks(String.t()) :: String.t()
  defp escape_unbalanced_backticks(text) do
    # Count backticks - if odd number, escape isolated ones
    # Strategy: find and escape backticks that are:
    # 1. At end of word followed by non-backtick (like $...$`)
    # 2. Isolated (not part of `code` pair)

    # First, protect valid inline code by replacing with placeholder
    text
    |> protect_inline_code()
    |> escape_remaining_backticks()
    |> restore_inline_code()
  end

  # Protect valid `inline code` patterns
  @spec protect_inline_code(String.t()) :: String.t()
  defp protect_inline_code(text) do
    # Match `...` (single backtick pairs) and protect them
    # Be careful not to match empty backticks ``
    Regex.replace(~r/`([^`]+)`/, text, "\x01IC:\\1\x01")
  end

  # Escape any remaining backticks that weren't part of inline code
  @spec escape_remaining_backticks(String.t()) :: String.t()
  defp escape_remaining_backticks(text) do
    String.replace(text, "`", "\\`")
  end

  # Restore protected inline code
  @spec restore_inline_code(String.t()) :: String.t()
  defp restore_inline_code(text) do
    Regex.replace(~r/\x01IC:([^\x01]+)\x01/, text, "`\\1`")
  end
end
