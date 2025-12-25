defmodule SnakeBridge.Generator.MetaGenerator do
  @moduledoc """
  Generates the _meta.ex file for discovery helpers.

  This module creates a Meta module for each generated Python library adapter
  that provides introspection functions like `functions/0`, `classes/0`,
  `submodules/0`, and `search/1`.

  ## Example

  For a library like `numpy`, this generates:

      defmodule Numpy.Meta do
        @moduledoc false

        @functions [
          {:array, 1, Numpy, "Create an array from a list"},
          {:zeros, 1, Numpy.Linalg, "Matrix of zeros"},
          ...
        ]

        @classes [
          {Numpy.Ndarray, "N-dimensional array"},
          ...
        ]

        @submodules [Numpy, Numpy.Linalg, Numpy.Fft]

        def functions, do: @functions
        def classes, do: @classes
        def submodules, do: @submodules

        def search(query) do
          query = String.downcase(query)
          Enum.filter(@functions, fn {name, _, _, doc} ->
            String.contains?(Atom.to_string(name), query) or
            String.contains?(String.downcase(doc), query)
          end)
        end
      end

  """

  @doc """
  Generates the source code for a _meta.ex file.

  ## Parameters

    * `module_name` - The base module name (e.g., "Numpy")
    * `functions_by_module` - Map of module => list of function info maps
    * `classes` - List of class info maps

  ## Returns

  A string containing formatted Elixir source code for the Meta module.

  ## Examples

      iex> MetaGenerator.generate("Numpy", %{Numpy => [...]}, [...])
      "defmodule Numpy.Meta do\\n..."

  """
  @spec generate(String.t() | atom() | Macro.t(), map(), list(map())) :: String.t()
  def generate(module_name, functions_by_module, classes) when is_map(functions_by_module) do
    module_name_str = module_to_string(module_name)
    meta_module = parse_module_name("#{module_name_str}.Meta")

    # Build function list
    functions_list = build_functions_list(functions_by_module)

    # Build classes list
    classes_list = build_classes_list(module_name_str, classes)

    # Build submodules list
    submodules_list = build_submodules_list(functions_by_module)

    module_ast =
      quote do
        defmodule unquote(meta_module) do
          @moduledoc false

          @functions unquote(functions_list)
          @classes unquote(classes_list)
          @submodules unquote(submodules_list)

          @doc """
          Returns all functions across all submodules.

          Each entry is a tuple of `{name, arity, module, doc}`.
          """
          @spec functions() :: list({atom(), non_neg_integer(), module(), String.t()})
          def functions, do: @functions

          @doc """
          Returns all classes with their documentation.

          Each entry is a tuple of `{module, doc}`.
          """
          @spec classes() :: list({module(), String.t()})
          def classes, do: @classes

          @doc """
          Returns all submodules.
          """
          @spec submodules() :: list(module())
          def submodules, do: @submodules

          @doc """
          Searches functions by name or documentation.

          Returns a list of functions matching the query string.
          Search is case-insensitive.

          ## Parameters

            * `query` - Search string

          ## Returns

          List of matching functions in the same format as `functions/0`.
          """
          @spec search(String.t()) :: list({atom(), non_neg_integer(), module(), String.t()})
          def search(query) when is_binary(query) do
            query_lower = String.downcase(query)

            Enum.filter(@functions, fn {name, _arity, _module, doc} ->
              name_str = Atom.to_string(name)
              doc_lower = String.downcase(doc)

              String.contains?(name_str, query_lower) or
                String.contains?(doc_lower, query_lower)
            end)
          end
        end
      end

    module_ast
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  # Private Functions

  @spec build_functions_list(map()) :: Macro.t()
  defp build_functions_list(functions_by_module) do
    function_tuples =
      functions_by_module
      |> Enum.flat_map(fn {module, functions} ->
        Enum.map(functions, fn func_info ->
          func_name = func_info["name"] |> to_elixir_function_name() |> String.to_atom()
          params = Map.get(func_info, "parameters", [])
          arity = length(params)

          doc =
            case func_info["docstring"] do
              %{"summary" => summary} when is_binary(summary) -> summary
              _ -> func_info["name"]
            end

          module_atom = module_name_to_atom(module)

          {func_name, arity, module_atom, doc}
        end)
      end)

    Macro.escape(function_tuples)
  end

  @spec build_classes_list(String.t(), list(map())) :: Macro.t()
  defp build_classes_list(base_module, classes) do
    class_tuples =
      Enum.map(classes, fn class_info ->
        class_name = class_info["name"]

        doc =
          case class_info["docstring"] do
            %{"summary" => summary} when is_binary(summary) -> summary
            _ -> class_name
          end

        module_atom = module_name_to_atom("#{base_module}.#{class_name}")

        {module_atom, doc}
      end)

    Macro.escape(class_tuples)
  end

  @spec build_submodules_list(map()) :: Macro.t()
  defp build_submodules_list(functions_by_module) do
    submodules =
      functions_by_module
      |> Map.keys()
      |> Enum.map(&module_name_to_atom/1)
      |> Enum.sort()

    Macro.escape(submodules)
  end

  @spec module_to_string(String.t() | atom() | Macro.t()) :: String.t()
  defp module_to_string(module) when is_binary(module), do: module

  defp module_to_string(module) when is_atom(module) do
    module |> Module.split() |> Enum.join(".")
  end

  defp module_to_string({:__aliases__, _, parts}) do
    parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
  end

  @spec module_name_to_atom(String.t() | atom() | Macro.t()) :: atom()
  defp module_name_to_atom(name) when is_atom(name), do: name

  defp module_name_to_atom({:__aliases__, _, parts}) do
    parts
    |> Module.concat()
  end

  defp module_name_to_atom(name) when is_binary(name) do
    name
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
    |> Module.concat()
  end

  @spec parse_module_name(String.t()) :: Macro.t()
  defp parse_module_name(name) when is_binary(name) do
    parts =
      name
      |> String.split(".")
      |> Enum.map(&String.to_atom/1)

    {:__aliases__, [alias: false], parts}
  end

  @spec to_elixir_function_name(String.t()) :: String.t()
  defp to_elixir_function_name(name) do
    name
    |> Macro.underscore()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> ensure_valid_identifier()
  end

  @spec ensure_valid_identifier(String.t()) :: String.t()
  defp ensure_valid_identifier(name) do
    case name do
      <<first::utf8, _rest::binary>> when first >= ?a and first <= ?z ->
        name

      <<first::utf8, _rest::binary>> when first == ?_ ->
        name

      <<first::utf8, _rest::binary>> when first >= ?0 and first <= ?9 ->
        "_" <> name

      "" ->
        "_unnamed"

      _ ->
        "_" <> name
    end
  end
end
