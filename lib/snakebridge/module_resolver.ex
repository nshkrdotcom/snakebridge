defmodule SnakeBridge.ModuleResolver do
  @moduledoc """
  Resolves ambiguous module paths to class attributes or submodules.
  """

  alias SnakeBridge.Introspector

  @type resolution ::
          {:class, String.t(), String.t()}
          | {:submodule, String.t()}
          | {:error, term()}

  @doc """
  Determines if an Elixir module maps to a Python class attribute or submodule.

  Returns:
    - `{:class, class_name, parent_module}` when the last path segment is a class.
    - `{:submodule, module_path}` when the path resolves to a submodule.
    - `{:error, reason}` when introspection fails.
  """
  @spec resolve_class_or_submodule(map(), module()) :: resolution()
  def resolve_class_or_submodule(library, elixir_module) do
    module_parts = Module.split(elixir_module)
    library_parts = Module.split(library.module_name)
    extra_parts = Enum.drop(module_parts, length(library_parts))

    case extra_parts do
      [] ->
        {:submodule, library.python_name}

      _ ->
        {parent_parts, [candidate]} = Enum.split(extra_parts, -1)
        parent_module = build_parent_module(library.python_name, parent_parts)

        case class_or_module(parent_module, candidate) do
          {:class, class_name} ->
            {:class, class_name, parent_module}

          {:module, module_name} ->
            {:submodule, join_module(parent_module, module_name)}

          :unknown ->
            {:submodule, fallback_submodule(library.python_name, extra_parts)}

          {:error, _} = error ->
            error
        end
    end
  end

  defp class_or_module(parent_module, candidate) do
    case introspect_attribute_type(parent_module, candidate) do
      {:ok, :class} ->
        {:class, candidate}

      {:ok, :module} ->
        {:module, candidate}

      {:ok, :other} ->
        maybe_downcase(parent_module, candidate)

      {:error, _} = error ->
        error
    end
  end

  defp maybe_downcase(parent_module, candidate) do
    downcased = String.downcase(candidate)

    if downcased == candidate do
      :unknown
    else
      case introspect_attribute_type(parent_module, downcased) do
        {:ok, :class} -> {:class, downcased}
        {:ok, :module} -> {:module, downcased}
        {:ok, :other} -> :unknown
        {:error, _} = error -> error
      end
    end
  end

  defp introspect_attribute_type(module_path, attr_name) do
    case Introspector.introspect_attribute(module_path, attr_name) do
      {:ok, %{"exists" => false}} ->
        {:ok, :other}

      {:ok, %{"is_class" => true}} ->
        {:ok, :class}

      {:ok, %{"is_module" => true}} ->
        {:ok, :module}

      {:ok, _} ->
        {:ok, :other}

      {:error, _} = error ->
        error
    end
  end

  defp build_parent_module(base, []), do: base

  defp build_parent_module(base, parts) do
    base <> "." <> Enum.map_join(parts, ".", &Macro.underscore/1)
  end

  defp fallback_submodule(base, parts) do
    [base | Enum.map(parts, &Macro.underscore/1)]
    |> Enum.join(".")
  end

  defp join_module(parent, child), do: parent <> "." <> child
end
