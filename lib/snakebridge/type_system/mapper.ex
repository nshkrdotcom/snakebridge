defmodule SnakeBridge.TypeSystem.Mapper do
  @moduledoc """
  Maps between Python type system and Elixir typespecs.
  """

  @doc """
  Convert Python type descriptor to Elixir typespec AST.
  """
  def to_elixir_spec(%{kind: "primitive", primitive_type: "int"}), do: quote(do: integer())
  def to_elixir_spec(%{kind: "primitive", primitive_type: "str"}), do: quote(do: String.t())
  def to_elixir_spec(%{kind: "primitive", primitive_type: "float"}), do: quote(do: float())
  def to_elixir_spec(%{kind: "primitive", primitive_type: "bool"}), do: quote(do: boolean())
  def to_elixir_spec(%{kind: "primitive", primitive_type: "bytes"}), do: quote(do: binary())
  def to_elixir_spec(%{kind: "primitive", primitive_type: "none"}), do: quote(do: nil)
  def to_elixir_spec(%{kind: "primitive", primitive_type: "any"}), do: quote(do: term())

  def to_elixir_spec(%{kind: "list", element_type: element}) do
    inner = to_elixir_spec(element)
    quote do: [unquote(inner)]
  end

  def to_elixir_spec(%{kind: "dict", key_type: key, value_type: value}) do
    key_spec = to_elixir_spec(key)
    value_spec = to_elixir_spec(value)
    quote do: %{optional(unquote(key_spec)) => unquote(value_spec)}
  end

  def to_elixir_spec(%{kind: "union", union_types: types}) do
    types
    |> Enum.map(&to_elixir_spec/1)
    |> Enum.reduce(fn spec, acc ->
      quote do: unquote(acc) | unquote(spec)
    end)
  end

  def to_elixir_spec(%{kind: "class", class_path: path}) do
    module = python_class_to_elixir_module(path)
    quote do: unquote(module).t()
  end

  def to_elixir_spec(_), do: quote(do: term())

  @doc """
  Infer Python type from Elixir value.
  """
  def infer_python_type(value) when is_integer(value), do: :int
  def infer_python_type(value) when is_float(value), do: :float
  def infer_python_type(value) when is_binary(value), do: :str
  def infer_python_type(value) when is_boolean(value), do: :bool
  def infer_python_type(nil), do: :none

  def infer_python_type([]), do: {:list, :any}

  def infer_python_type([first | _]) do
    {:list, infer_python_type(first)}
  end

  def infer_python_type(map) when is_map(map) and map_size(map) == 0 do
    {:dict, :str, :any}
  end

  def infer_python_type(map) when is_map(map) do
    keys = Map.keys(map)
    vals = Map.values(map)

    if length(keys) > 0 do
      [key | _] = keys
      [val | _] = vals

      # Infer key type - handle atoms by converting to string first
      key_type =
        cond do
          is_atom(key) -> :str
          true -> infer_python_type(key)
        end

      # Infer value type - if multiple values have different types, use :any
      val_type =
        vals
        |> Enum.map(&infer_python_type/1)
        |> Enum.uniq()
        |> case do
          [single_type] -> single_type
          _ -> :any
        end

      {:dict, key_type, val_type}
    else
      {:dict, :str, :any}
    end
  end

  @doc """
  Convert Python class path to Elixir module atom.

  Handles atom length limits by using String.to_existing_atom when possible,
  or creating a safe shortened version.
  """
  def python_class_to_elixir_module(python_path) when is_binary(python_path) do
    # Convert python.module.Class to Elixir module atom
    # Capitalize each part, preserving acronyms (e.g., "dspy" -> "DSPy")
    parts =
      python_path
      |> String.split(".")
      |> Enum.map(&smart_capitalize/1)

    module_string = Module.concat(parts) |> Atom.to_string()

    # Atoms have a 255 byte limit
    if byte_size(module_string) > 255 do
      # Use hash for very long paths
      hash = :crypto.hash(:sha256, python_path) |> Base.encode16() |> String.slice(0..7)
      String.to_atom("Module_#{hash}")
    else
      Module.concat(parts)
    end
  end

  # Smart capitalization that preserves common acronyms and CamelCase
  defp smart_capitalize("dspy"), do: "DSPy"
  defp smart_capitalize("ai"), do: "AI"
  defp smart_capitalize("ml"), do: "ML"
  defp smart_capitalize("nlp"), do: "NLP"

  defp smart_capitalize(str) do
    # If string contains uppercase letters, it's likely already CamelCase - preserve it
    if String.match?(str, ~r/[A-Z]/) do
      str
    else
      String.capitalize(str)
    end
  end
end
