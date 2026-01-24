defmodule SnakeBridge.Docs.ManifestBuilder do
  @moduledoc """
  Builds docs surface manifests from published documentation artifacts.

  Primary input is a Sphinx `objects.inv` inventory (Intersphinx format).
  Optionally, an HTML page can be used to derive a curated "summary" profile
  by extracting fully-qualified object references and intersecting them with
  the inventory.
  """

  alias SnakeBridge.Docs.SphinxInventory

  @type profile_name :: String.t()
  @type kind :: String.t()

  @type object_entry :: map()
  @type profile :: map()
  @type manifest :: map()

  @doc """
  Builds a manifest from a parsed Sphinx inventory.
  """
  @spec from_inventory(SphinxInventory.t(), String.t(), keyword()) :: profile()
  def from_inventory(%{entries: entries}, library_root, opts \\ [])
      when is_binary(library_root) do
    module_allowlist = normalize_module_allowlist_opt(opts, library_root)
    all_objects = build_objects(entries, library_root)
    all_objects = drop_class_member_objects(all_objects)
    full_objects = filter_objects_by_module_allowlist(all_objects, module_allowlist)
    modules = build_modules(entries, library_root, full_objects, module_allowlist)

    %{
      "modules" => modules,
      "objects" => Enum.sort_by(full_objects, & &1["name"])
    }
  end

  defp normalize_module_allowlist_opt(opts, library_root) do
    opts
    |> Keyword.get(:module_allowlist)
    |> case do
      nil -> nil
      list when is_list(list) -> MapSet.new(list)
      %MapSet{} = set -> set
      _ -> nil
    end
    |> normalize_module_allowlist(library_root)
  end

  defp build_objects(entries, library_root) do
    entries
    |> Enum.flat_map(&object_from_entry(&1, library_root))
    |> Enum.uniq_by(&{&1["name"], &1["kind"]})
  end

  # Sphinx inventories frequently include class members like:
  #
  # - `examplelib.config.Config.from_env` as `py:function`
  #
  # In SnakeBridge, those members are generated via class introspection, not as
  # standalone module functions. Treating them as module functions produces
  # bogus "modules" like `examplelib.config.Config` which are not importable.
  defp drop_class_member_objects(objects) do
    class_names =
      objects
      |> Enum.filter(&(&1["kind"] == "class"))
      |> Enum.map(& &1["name"])
      |> MapSet.new()

    Enum.reject(objects, &class_member_object?(&1, class_names))
  end

  defp class_member_object?(%{"kind" => kind} = obj, class_names)
       when kind in ["function", "data"] do
    case module_for_object(obj) do
      nil -> false
      parent -> MapSet.member?(class_names, parent)
    end
  end

  defp class_member_object?(_obj, _class_names), do: false

  defp filter_objects_by_module_allowlist(objects, nil), do: objects

  defp filter_objects_by_module_allowlist(objects, %MapSet{} = allowlist) do
    Enum.filter(objects, &object_module_allowed?(&1, allowlist))
  end

  defp object_module_allowed?(obj, allowlist) do
    case module_for_object(obj) do
      nil -> false
      python_module -> MapSet.member?(allowlist, python_module)
    end
  end

  defp build_modules(entries, library_root, objects, nil) do
    inventory_modules =
      entries
      |> Enum.filter(&module_entry?(&1, library_root))
      |> Enum.map(& &1.name)

    (inventory_modules ++ modules_from_objects(objects) ++ [library_root])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp build_modules(entries, library_root, objects, %MapSet{} = allowlist) do
    inventory_modules =
      entries
      |> Enum.filter(&module_entry?(&1, library_root))
      |> Enum.map(& &1.name)
      |> Enum.filter(&MapSet.member?(allowlist, &1))

    (inventory_modules ++
       modules_from_objects(objects) ++ [library_root] ++ MapSet.to_list(allowlist))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Builds a summary profile by extracting object references from HTML and
  intersecting with a full profile built from inventory.
  """
  @spec summary_from_html(profile(), String.t(), String.t()) :: profile()
  def summary_from_html(full_profile, html, library_root)
      when is_binary(html) and is_binary(library_root) do
    referenced = extract_references_from_html(html, library_root)

    referenced_modules =
      full_profile["modules"]
      |> MapSet.new()
      |> MapSet.intersection(referenced)

    objects =
      full_profile["objects"]
      |> Enum.filter(&MapSet.member?(referenced, &1["name"]))

    modules =
      objects
      |> modules_from_objects()
      |> Kernel.++(MapSet.to_list(referenced_modules))
      |> Kernel.++([library_root])
      |> Enum.uniq()
      |> Enum.sort()

    %{"modules" => modules, "objects" => objects}
  end

  @doc """
  Merges two profiles by unioning modules and objects.

  Objects are deduplicated by `{name, kind}`.
  """
  @spec merge_profiles(profile(), profile()) :: profile()
  def merge_profiles(%{"modules" => modules_a, "objects" => objects_a}, %{
        "modules" => modules_b,
        "objects" => objects_b
      })
      when is_list(modules_a) and is_list(objects_a) and is_list(modules_b) and is_list(objects_b) do
    modules =
      (modules_a ++ modules_b)
      |> Enum.uniq()
      |> Enum.sort()

    objects =
      (objects_a ++ objects_b)
      |> Enum.uniq_by(&{&1["name"], &1["kind"]})
      |> Enum.sort_by(& &1["name"])

    %{"modules" => modules, "objects" => objects}
  end

  @doc """
  Returns a set of fully-qualified references found in HTML.
  """
  @spec extract_references_from_html(String.t(), String.t()) :: MapSet.t(String.t())
  def extract_references_from_html(html, library_root)
      when is_binary(html) and is_binary(library_root) do
    html =
      html
      |> String.replace(~r/<[^>]*>/, " ")
      |> String.replace("&nbsp;", " ")

    # Sphinx HTML typically contains identifiers like `examplelib.config.Config`.
    pattern =
      ~r/\b#{Regex.escape(library_root)}(?:\.[A-Za-z_][A-Za-z0-9_]*)+\b/

    Regex.scan(pattern, html)
    |> Enum.map(fn [match] -> match end)
    |> MapSet.new()
  end

  @doc """
  Extracts candidate module names from Sphinx/MkDocs-style nav links.

  Many documentation sites render module pages as paths like:

  - `examplelib/beam_search/` → `examplelib.beam_search`
  - `examplelib/v1/worker/gpu/` → `examplelib.v1.worker.gpu`
  """
  @spec extract_modules_from_html_nav(String.t(), String.t()) :: MapSet.t(String.t())
  def extract_modules_from_html_nav(html, library_root)
      when is_binary(html) and is_binary(library_root) do
    pattern =
      ~r/\bhref=(?:"|')?(?:\.\.\/|\.\/|\/)?(#{Regex.escape(library_root)}\/[A-Za-z0-9_\/-]+)\/?(?:"|')?/i

    Regex.scan(pattern, html)
    |> Enum.map(&nav_match_path/1)
    |> Enum.flat_map(&nav_path_to_modules(&1, library_root))
    |> MapSet.new()
  end

  defp nav_match_path([_, path]), do: path
  defp nav_match_path([path]), do: path

  defp nav_path_to_modules(path, library_root) do
    path
    |> sanitize_nav_path()
    |> String.split("/", trim: true)
    |> segments_to_modules(library_root)
  end

  defp sanitize_nav_path(path) do
    path
    |> String.split(~r/[?#]/, parts: 2)
    |> hd()
    |> String.trim_leading("/")
  end

  defp segments_to_modules([root], root), do: [root]

  defp segments_to_modules([root | rest], root) do
    rest
    |> normalize_nav_segments()
    |> build_nav_module(root)
  end

  defp segments_to_modules(_segments, _root), do: []

  defp normalize_nav_segments(segments) do
    segments
    |> Enum.map(&String.replace_suffix(&1, ".html", ""))
    |> Enum.reject(&(&1 in ["", "index"]))
    |> Enum.map(&String.replace(&1, "-", "_"))
  end

  defp build_nav_module([], library_root), do: [library_root]

  defp build_nav_module(segments, library_root) do
    if Enum.all?(segments, &valid_module_segment?/1) do
      [library_root <> "." <> Enum.join(segments, ".")]
    else
      []
    end
  end

  defp valid_module_segment?(segment) do
    Regex.match?(~r/^[a-z_][a-z0-9_]*$/, segment)
  end

  @doc """
  Filters a set/list of Python module names to a maximum depth relative to `library_root`.

  Depth is measured in dot-separated segments *after* the root:

  - `examplelib.config` → depth 1
  - `examplelib.multimodal.inputs` → depth 2
  """
  @spec filter_modules_by_depth(Enumerable.t(), String.t(), pos_integer()) ::
          MapSet.t(String.t())
  def filter_modules_by_depth(modules, library_root, depth)
      when is_binary(library_root) and is_integer(depth) and depth > 0 do
    modules
    |> Enum.filter(fn
      ^library_root ->
        true

      module when is_binary(module) ->
        if String.starts_with?(module, library_root <> ".") do
          relative = String.replace_prefix(module, library_root <> ".", "")
          length(String.split(relative, ".")) <= depth
        else
          false
        end

      _ ->
        false
    end)
    |> MapSet.new()
  end

  defp normalize_module_allowlist(nil, _library_root), do: nil

  defp normalize_module_allowlist(%MapSet{} = allowlist, library_root) do
    allowlist
    |> Enum.map(&to_string/1)
    |> Enum.filter(fn mod ->
      mod == library_root or String.starts_with?(mod, library_root <> ".")
    end)
    |> MapSet.new()
  end

  defp module_entry?(%{domain_role: "py:module", name: name}, library_root) do
    String.starts_with?(name, library_root <> ".") or name == library_root
  end

  defp module_entry?(_entry, _library_root), do: false

  defp object_from_entry(%{name: name, domain_role: domain_role}, library_root) do
    if String.starts_with?(name, library_root <> ".") or name == library_root do
      case domain_role do
        "py:class" -> [%{"name" => name, "kind" => "class"}]
        "py:function" -> [%{"name" => name, "kind" => "function"}]
        "py:data" -> [%{"name" => name, "kind" => "data"}]
        "py:attribute" -> [%{"name" => name, "kind" => "data"}]
        _ -> []
      end
    else
      []
    end
  end

  defp object_from_entry(_entry, _library_root), do: []

  defp modules_from_objects(objects) when is_list(objects) do
    objects
    |> Enum.map(&module_for_object/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp module_for_object(%{"name" => name}) when is_binary(name) do
    case String.split(name, ".") do
      [_single] -> nil
      parts -> parts |> Enum.drop(-1) |> Enum.join(".")
    end
  end

  defp module_for_object(_), do: nil
end
