defmodule SnakeBridge.Manifest do
  @moduledoc """
  Manifest storage for generated symbols.
  """

  @spec load(SnakeBridge.Config.t()) :: map()
  def load(config) do
    path = manifest_path(config)

    case File.read(path) do
      {:ok, content} ->
        content
        |> Jason.decode!()
        |> normalize_manifest()

      {:error, :enoent} ->
        %{"version" => version(), "symbols" => %{}, "classes" => %{}, "modules" => %{}}
    end
  end

  @spec save(SnakeBridge.Config.t(), map()) :: :ok
  def save(config, manifest) do
    path = manifest_path(config)
    File.mkdir_p!(Path.dirname(path))

    manifest
    |> Map.put("version", version())
    |> sort_manifest()
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(path, &1))
  end

  @spec missing(map(), list({module(), atom(), non_neg_integer()})) ::
          list({module(), atom(), non_neg_integer()})
  def missing(manifest, detected) do
    classes = Map.get(manifest, "classes", %{})

    detected
    |> Enum.reject(fn {mod, func, arity} ->
      module_key = module_to_string(mod)

      case Map.get(classes, module_key) do
        nil -> call_supported?(manifest, mod, func, arity)
        class_info -> class_call_supported?(class_info, func, arity)
      end
    end)
  end

  @spec call_supported?(map(), module(), atom(), non_neg_integer()) :: boolean()
  def call_supported?(manifest, module, function, call_site_arity) do
    prefix = "#{module_to_string(module)}.#{function}/"

    manifest
    |> Map.get("symbols", %{})
    |> Enum.any?(fn {key, info} ->
      String.starts_with?(key, prefix) and
        symbol_arity_matches?(key, info, call_site_arity)
    end)
  end

  defp symbol_arity_matches?(key, info, call_site_arity) do
    arity_from_key = symbol_arity_from_key(key)
    min_arity = info["minimum_arity"] || info["required_arity"] || arity_from_key || 0
    max_arity = info["maximum_arity"] || arity_from_key
    has_var_positional = info["has_var_positional"] == true

    arity_in_range?(call_site_arity, min_arity, max_arity, has_var_positional)
  end

  defp arity_in_range?(call_site_arity, min_arity, max_arity, has_var_positional) do
    cond do
      max_arity in [:unbounded, "unbounded"] or has_var_positional ->
        call_site_arity >= min_arity

      is_integer(max_arity) ->
        call_site_arity >= min_arity and call_site_arity <= max_arity

      true ->
        call_site_arity == min_arity
    end
  end

  defp class_call_supported?(class_info, function, call_site_arity) do
    function_name = to_string(function)
    methods = method_field(class_info, "methods") || []
    attrs = method_field(class_info, "attributes") || []

    if methods == [] and attrs == [] do
      true
    else
      method_supported? =
        Enum.any?(methods, fn method ->
          method_name(method) == function_name and
            method_arity_supported?(method, call_site_arity)
        end)

      attr_supported? =
        Enum.any?(attrs, fn attr ->
          to_string(attr) == function_name and call_site_arity == 1
        end)

      method_supported? or attr_supported?
    end
  end

  defp method_name(method) do
    method_field(method, "elixir_name") ||
      case method_field(method, "name") do
        "__init__" -> "new"
        name when is_binary(name) -> name
        _ -> ""
      end
  end

  defp method_arity_supported?(method, call_site_arity) do
    {min_arity, max_arity, has_var_positional} = method_arity_info(method)
    arity_in_range?(call_site_arity, min_arity, max_arity, has_var_positional)
  end

  defp method_arity_info(method) do
    min_arity = method_field(method, "minimum_arity")
    max_arity = method_field(method, "maximum_arity")
    required_arity = method_field(method, "required_arity")
    has_var_positional = method_field(method, "has_var_positional") == true

    if has_explicit_arity_info?(min_arity, max_arity, has_var_positional) do
      {min_arity || required_arity || 0, max_arity, has_var_positional}
    else
      compute_arity_from_params(method)
    end
  end

  defp has_explicit_arity_info?(min_arity, max_arity, has_var_positional) do
    is_integer(min_arity) or is_integer(max_arity) or has_var_positional
  end

  defp compute_arity_from_params(method) do
    params = method_field(method, "parameters") || []
    signature_available = method_field(method, "signature_available") != false
    raw_name = method_field(method, "name") || ""

    {min_base, max_base, var_positional?} =
      compute_method_arity(params, signature_available)

    ref_offset = if raw_name == "__init__", do: 0, else: 1
    apply_ref_offset(min_base, max_base, ref_offset, var_positional?)
  end

  defp apply_ref_offset(min_base, max_base, ref_offset, var_positional?) do
    min_arity = min_base + ref_offset

    max_arity =
      case max_base do
        :unbounded -> :unbounded
        value when is_integer(value) -> value + ref_offset
        _ -> min_arity
      end

    {min_arity, max_arity, var_positional?}
  end

  defp compute_method_arity(params, signature_available) do
    positional_params =
      Enum.filter(params, fn param ->
        param_kind(param) in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]
      end)

    required_positional =
      positional_params
      |> Enum.reject(&param_default?/1)
      |> length()

    optional_positional =
      positional_params
      |> Enum.filter(&param_default?/1)
      |> length()

    has_var_positional = Enum.any?(params, &varargs?/1)
    variadic_fallback = params == [] and signature_available == false

    max_arity =
      cond do
        variadic_fallback -> variadic_max_arity() + 1
        has_var_positional -> :unbounded
        optional_positional > 0 -> required_positional + 2
        true -> required_positional + 1
      end

    {required_positional, max_arity, has_var_positional}
  end

  defp variadic_max_arity do
    Application.get_env(:snakebridge, :variadic_max_arity, 8)
  end

  defp varargs?(param), do: param_kind(param) == "VAR_POSITIONAL"

  defp param_kind(%{"kind" => kind}) when is_binary(kind), do: String.upcase(kind)
  defp param_kind(%{kind: kind}) when is_binary(kind), do: String.upcase(kind)
  defp param_kind(%{kind: kind}), do: kind
  defp param_kind(_), do: nil

  defp param_default?(%{"default" => _}), do: true
  defp param_default?(%{default: _}), do: true
  defp param_default?(_), do: false

  defp method_field(map, key) when is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp symbol_arity_from_key(key) when is_binary(key) do
    case String.split(key, "/") do
      [_prefix, arity] ->
        case Integer.parse(arity) do
          {value, ""} -> value
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec put_symbols(map(), list({String.t(), map()})) :: map()
  def put_symbols(manifest, entries) do
    symbols =
      manifest
      |> Map.get("symbols", %{})
      |> Map.merge(Map.new(entries))

    Map.put(manifest, "symbols", symbols)
  end

  @spec put_classes(map(), list({String.t(), map()})) :: map()
  def put_classes(manifest, entries) do
    classes =
      manifest
      |> Map.get("classes", %{})
      |> Map.merge(Map.new(entries))

    Map.put(manifest, "classes", classes)
  end

  @spec put_modules(map(), list({String.t(), map()})) :: map()
  def put_modules(manifest, entries) do
    modules =
      manifest
      |> Map.get("modules", %{})
      |> Map.merge(Map.new(entries))

    Map.put(manifest, "modules", modules)
  end

  @spec symbol_key({module(), atom(), non_neg_integer()}) :: String.t()
  def symbol_key({module, function, arity}) do
    mod = module |> Module.split() |> Enum.join(".")
    "#{mod}.#{function}/#{arity}"
  end

  @spec class_key(module()) :: String.t()
  def class_key(module) when is_atom(module) do
    Module.split(module) |> Enum.join(".")
  end

  defp module_to_string(module) when is_atom(module) do
    Module.split(module) |> Enum.join(".")
  end

  defp manifest_path(config) do
    Path.join(config.metadata_dir, "manifest.json")
  end

  defp version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end

  defp normalize_manifest(manifest) do
    symbols = Map.get(manifest, "symbols", %{})
    modules = Map.get(manifest, "modules", %{})

    normalized_symbols =
      Enum.reduce(symbols, %{}, fn {key, value}, acc ->
        normalized = normalize_symbol_key(key)

        if normalized == key do
          Map.put(acc, normalized, value)
        else
          Map.put_new(acc, normalized, value)
        end
      end)

    manifest
    |> Map.put("symbols", normalized_symbols)
    |> Map.put("modules", modules)
  end

  defp normalize_symbol_key(key) when is_binary(key) do
    case String.split(key, ".") do
      ["Elixir" | rest] ->
        case Enum.split(rest, -1) do
          {module_parts, [fun_part]} when module_parts != [] ->
            Enum.join(module_parts, ".") <> "." <> fun_part

          _ ->
            key
        end

      _ ->
        key
    end
  end

  defp normalize_symbol_key(key), do: key

  defp sort_manifest(manifest) do
    manifest
    |> update_in(["symbols"], fn symbols ->
      symbols
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Map.new()
    end)
    |> update_in(["classes"], fn classes ->
      classes
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Map.new()
    end)
    |> Map.update("modules", %{}, fn modules ->
      modules
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Map.new()
    end)
  end
end
