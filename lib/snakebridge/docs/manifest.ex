defmodule SnakeBridge.Docs.Manifest do
  @moduledoc """
  Loads a docs-derived public surface manifest for a SnakeBridge library.

  A manifest is a JSON file that encodes which Python modules/objects should be
  treated as the "public surface" for wrapper generation. This enables:

  - small, stable default bindings (e.g. `:summary`)
  - an opt-in "everything the docs publish" surface (e.g. `:full`)
  - deterministic builds without walking large Python package trees
  """

  @type object_kind :: :class | :function | :data | :unknown

  @type object_entry :: %{
          required(:name) => String.t(),
          required(:kind) => object_kind()
        }

  @type profile :: %{
          required(:modules) => [String.t()],
          required(:objects) => [object_entry()]
        }

  @spec load_profile(SnakeBridge.Config.Library.t()) :: {:ok, profile()} | {:error, term()}
  def load_profile(%{docs_manifest: nil}), do: {:error, :no_docs_manifest}

  def load_profile(%{docs_manifest: path} = library) when is_binary(path) do
    profile =
      case Map.get(library, :docs_profile) do
        nil -> "full"
        value when is_binary(value) -> value
        value when is_atom(value) -> Atom.to_string(value)
        value -> to_string(value)
      end

    with {:ok, content} <- File.read(path),
         {:ok, decoded} <- Jason.decode(content),
         :ok <- validate_library(decoded, library),
         {:ok, profile_data} <- fetch_profile(decoded, profile) do
      normalize_profile(profile_data)
    end
  end

  defp validate_library(%{"library" => expected}, %{python_name: python_name})
       when is_binary(expected) and is_binary(python_name) do
    if expected == python_name do
      :ok
    else
      {:error, {:manifest_library_mismatch, expected, python_name}}
    end
  end

  defp validate_library(_decoded, _library), do: :ok

  defp fetch_profile(decoded, profile) when is_binary(profile) do
    profiles = Map.get(decoded, "profiles") || %{}

    case Map.get(profiles, profile) do
      nil -> {:error, {:unknown_profile, profile, Map.keys(profiles)}}
      data -> {:ok, data}
    end
  end

  defp normalize_profile(%{"modules" => modules, "objects" => objects})
       when is_list(modules) and is_list(objects) do
    modules =
      modules
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    objects =
      objects
      |> Enum.flat_map(fn
        %{"name" => name} = obj when is_binary(name) ->
          kind = normalize_kind(Map.get(obj, "kind"))
          [%{name: name, kind: kind}]

        _ ->
          []
      end)

    {:ok, %{modules: modules, objects: objects}}
  end

  defp normalize_profile(_), do: {:error, :invalid_manifest_profile}

  defp normalize_kind("class"), do: :class
  defp normalize_kind("function"), do: :function
  defp normalize_kind("data"), do: :data
  defp normalize_kind(kind) when is_atom(kind), do: kind
  defp normalize_kind(_), do: :unknown
end
