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
      |> Enum.reject(&is_nil_or_empty?/1)

    case parts do
      [] -> nil
      _ -> Enum.join(parts, "\n\n")
    end
  end

  defp format_summary_and_description(%{"summary" => summary}) when not is_nil(summary) do
    summary
  end

  defp format_summary_and_description(%{"description" => description})
       when not is_nil(description) do
    description
  end

  defp format_summary_and_description(%{"raw" => raw}) when not is_nil(raw) do
    raw
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
        {doc["name"], doc["description"]}
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
    case type do
      "int" -> "integer"
      "str" -> "string"
      "bool" -> "boolean"
      "float" -> "float"
      "list" -> "list"
      "dict" -> "map"
      "tuple" -> "tuple"
      "set" -> "set"
      "none" -> "nil"
      _ -> type
    end
  end

  defp format_param_type(_), do: ""

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
        [description | parts]
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
        description = exc["description"] || ""

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
    "## Examples\n\n#{examples}"
  end

  defp format_examples(_), do: nil

  @spec is_nil_or_empty?(String.t() | nil) :: boolean()
  defp is_nil_or_empty?(nil), do: true
  defp is_nil_or_empty?(""), do: true
  defp is_nil_or_empty?(_), do: false

  @spec default_if_empty(String.t(), String.t()) :: String.t()
  defp default_if_empty("", default), do: default
  defp default_if_empty(value, _default), do: value
end
