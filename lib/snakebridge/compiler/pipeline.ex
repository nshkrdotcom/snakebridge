defmodule SnakeBridge.Compiler.Pipeline do
  @moduledoc false

  alias SnakeBridge.{
    Config,
    Docs,
    Generator,
    Generator.PathMapper,
    HelperGenerator,
    Helpers,
    Lock,
    Manifest,
    ModuleResolver,
    PythonEnv,
    Scanner,
    Telemetry
  }

  alias SnakeBridge.Compiler.IntrospectionRunner

  @reserved_words ~w(def defp defmodule class do end if unless case cond for while with fn when and or not true false nil in try catch rescue after else raise throw receive)

  @spec run(Config.t()) :: {:ok, []}
  def run(config) do
    run_with_config(config)
  end

  def run_with_config(%{libraries: []}), do: {:ok, []}

  def run_with_config(config) do
    case strict_mode?(config) do
      true ->
        run_strict(config)

      _ ->
        PythonEnv.ensure!(config)
        with_introspector_config(config, fn -> run_normal(config) end)
    end
  end

  defp update_manifest(manifest, targets) do
    requested_kinds =
      targets
      |> Enum.map(fn {library, python_module, symbols} ->
        {{library, python_module}, symbol_kind_map(symbols)}
      end)
      |> Map.new()

    {updates, errors} = IntrospectionRunner.run(targets)

    updates =
      Enum.sort_by(updates, fn {library, python_module, _infos} ->
        root_priority =
          case python_module == library.python_name do
            true -> 0
            _ -> 1
          end

        module_depth = length(String.split(python_module, "."))
        {library.python_name, root_priority, module_depth, python_module}
      end)

    {existing_class_map, existing_class_modules} = existing_classes_from_manifest(manifest)
    reserved_modules = reserved_modules_from_manifest(manifest)

    {updated, _reserved_modules, _used_class_modules} =
      Enum.reduce(
        updates,
        {manifest, reserved_modules, existing_class_modules},
        fn {library, python_module, infos}, {acc, reserved, used_class_modules} ->
          infos =
            normalize_symbol_infos(
              library,
              python_module,
              infos,
              Map.get(requested_kinds, {library, python_module}, %{})
            )

          class_keys = class_keys_from_infos(infos, python_module)

          {symbol_entries, class_entries, reserved, used_class_modules} =
            build_manifest_entries(
              library,
              python_module,
              infos,
              reserved,
              used_class_modules,
              existing_class_map
            )

          acc =
            acc
            |> drop_class_entries(class_keys)
            |> Manifest.put_symbols(symbol_entries)
            |> Manifest.put_classes(class_entries)

          {acc, reserved, used_class_modules}
        end
      )

    {updated, errors}
  end

  defp symbol_kind_map(symbols) when is_list(symbols) do
    symbols
    |> Enum.reduce(%{}, fn
      {name, kind}, acc when is_binary(name) and kind in [:class, :function, :data, :unknown] ->
        Map.put(acc, name, kind)

      {name, kind}, acc when is_atom(name) and kind in [:class, :function, :data, :unknown] ->
        Map.put(acc, Atom.to_string(name), kind)

      name, acc when is_binary(name) ->
        acc

      name, acc when is_atom(name) ->
        acc

      _, acc ->
        acc
    end)
  end

  defp normalize_symbol_infos(library, python_module, infos, requested_kinds) do
    {ok_infos, not_found} =
      Enum.split_with(infos, fn info ->
        info["error"] != "not_found"
      end)

    handle_not_found_infos(ok_infos, not_found, library, python_module, requested_kinds)
  end

  defp handle_not_found_infos(ok_infos, [], _library, _python_module, _requested_kinds),
    do: ok_infos

  defp handle_not_found_infos(ok_infos, not_found, library, python_module, requested_kinds) do
    case on_not_found_mode(library) do
      :error ->
        raise_not_found!(not_found, python_module)

      :stub ->
        ok_infos ++ build_not_found_stubs(not_found, python_module, requested_kinds)
    end
  end

  defp raise_not_found!(not_found, python_module) do
    formatted =
      not_found
      |> Enum.map(& &1["name"])
      |> Enum.sort()
      |> Enum.map_join("\n", fn name -> "  - #{python_module}.#{name}" end)

    raise SnakeBridge.CompileError, """
    SnakeBridge could not find #{length(not_found)} symbol(s) in Python module #{python_module}.

    Missing:
    #{formatted}

    Fix by:
      - upgrading/downgrading the Python dependency version, or
      - removing/renaming the call in Elixir, or
      - setting `on_not_found: :stub` for this library to generate stubs.
    """
  end

  defp build_not_found_stubs(not_found, python_module, requested_kinds) do
    Enum.map(not_found, fn info ->
      name = info["name"] || ""
      kind = Map.get(requested_kinds, name) || heuristic_kind(name)
      not_found_stub_info(name, python_module, kind)
    end)
  end

  defp on_not_found_mode(%{on_not_found: mode}) when mode in [:error, :stub], do: mode
  defp on_not_found_mode(%{generate: :used}), do: :error
  defp on_not_found_mode(%{generate: :all}), do: :stub
  defp on_not_found_mode(_), do: :stub

  defp heuristic_kind(name) when is_binary(name) do
    case name do
      <<first::utf8, _::binary>> when first in ?A..?Z -> :class
      _ -> :function
    end
  end

  defp heuristic_kind(_), do: :unknown

  defp not_found_stub_info(name, python_module, :class) do
    %{
      "name" => name,
      "type" => "class",
      "python_module" => python_module,
      "docstring" => "",
      "doc_source" => "stub",
      "doc_missing_reason" => "symbol not found",
      "methods" => [
        %{
          "name" => "__init__",
          "parameters" => [],
          "return_type" => %{"type" => "any"},
          "signature_available" => false,
          "signature_source" => "stub",
          "signature_detail" => "variadic",
          "signature_missing_reason" => "symbol not found",
          "docstring" => "",
          "doc_source" => "stub",
          "doc_missing_reason" => "symbol not found"
        }
      ],
      "attributes" => []
    }
  end

  defp not_found_stub_info(name, python_module, _kind) do
    %{
      "name" => name,
      "type" => "function",
      "python_module" => python_module,
      "parameters" => [],
      "return_type" => %{"type" => "any"},
      "signature_available" => false,
      "signature_source" => "stub",
      "signature_detail" => "variadic",
      "signature_missing_reason" => "symbol not found",
      "docstring" => "",
      "doc_source" => "stub",
      "doc_missing_reason" => "symbol not found"
    }
  end

  defp build_targets(missing, config, manifest) do
    initial =
      Enum.reduce(missing, %{}, fn entry, acc ->
        accumulate_missing_target(entry, acc, config)
      end)

    with_includes =
      Enum.reduce(config.libraries, initial, fn library, acc ->
        includes =
          library.include
          |> Enum.reject(&function_or_class_present?(manifest, library, &1))

        accumulate_includes(includes, library, acc)
      end)

    with_includes
    |> Enum.map(fn {{library, python_module}, functions} ->
      filtered =
        functions
        |> Enum.reject(fn symbol -> symbol_request_name(symbol) in library.exclude end)
        |> uniq_symbol_requests()

      {library, python_module, filtered}
    end)
    |> Enum.reject(fn {_library, _python_module, functions} -> functions == [] end)
  end

  defp uniq_symbol_requests(symbols) when is_list(symbols) do
    symbols
    |> Enum.reduce(%{}, fn symbol, acc ->
      name = symbol_request_name(symbol)
      kind = symbol_request_kind(symbol)

      Map.update(acc, name, kind, fn existing ->
        preferred_kind(existing, kind)
      end)
    end)
    |> Enum.map(fn {name, kind} -> {name, kind} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp preferred_kind(:class, _), do: :class
  defp preferred_kind(_, :class), do: :class
  defp preferred_kind(:function, _), do: :function
  defp preferred_kind(_, :function), do: :function
  defp preferred_kind(existing, _), do: existing

  defp symbol_request_name({name, _kind}) when is_binary(name), do: name
  defp symbol_request_name({name, _kind}) when is_atom(name), do: Atom.to_string(name)
  defp symbol_request_name(name) when is_binary(name), do: name
  defp symbol_request_name(name) when is_atom(name), do: Atom.to_string(name)
  defp symbol_request_name(other), do: to_string(other)

  defp symbol_request_kind({_, kind}) when kind in [:class, :function, :data, :unknown], do: kind
  defp symbol_request_kind(_), do: :unknown

  defp apply_truncated_class_method_stubs(manifest, detected, _config) do
    missing = Manifest.missing(manifest, detected)

    {updated_manifest, unresolved} =
      Enum.reduce(missing, {manifest, []}, fn {mod, fun, _arity} = call,
                                              {acc_manifest, acc_unresolved} ->
        module_key = Manifest.class_key(mod)
        class_info = get_in(acc_manifest, ["classes", module_key])

        case class_info do
          %{"methods_truncated" => true} = class_info ->
            elixir_name = to_string(fun)
            python_name = python_name_for_elixir_name(elixir_name)

            updated =
              put_truncated_method_stub(
                acc_manifest,
                module_key,
                class_info,
                elixir_name,
                python_name
              )

            {updated, acc_unresolved}

          _ ->
            {acc_manifest, [call | acc_unresolved]}
        end
      end)

    unresolved = Enum.reverse(unresolved)
    {updated_manifest, unresolved}
  end

  defp put_truncated_method_stub(manifest, module_key, class_info, elixir_name, python_name) do
    methods = List.wrap(class_info["methods"])

    methods =
      methods
      |> Enum.reject(fn method ->
        (method["elixir_name"] || method["name"]) == elixir_name
      end)

    stub = %{
      "name" => python_name,
      "python_name" => python_name,
      "elixir_name" => elixir_name,
      "parameters" => [],
      "return_type" => %{"type" => "any"},
      "signature_available" => false,
      "signature_source" => "stub",
      "signature_detail" => "variadic",
      "signature_missing_reason" => "class methods truncated",
      "docstring" => "",
      "doc_source" => "stub",
      "doc_missing_reason" => "generated stub"
    }

    updated_class = Map.put(class_info, "methods", [stub | methods])

    update_in(manifest, ["classes"], fn classes ->
      Map.put(classes, module_key, updated_class)
    end)
  end

  defp accumulate_missing_target({module, function, _arity}, acc, config) do
    case library_for_module(config, module) do
      nil ->
        acc

      library ->
        case ModuleResolver.resolve_class_or_submodule(library, module) do
          {:class, class_name, parent_module} ->
            add_target(acc, library, parent_module, {class_name, :class})

          {:submodule, python_module} ->
            python_function = python_function_for_call(library, function)

            add_target(acc, library, python_module, {python_function, :function})

          {:error, _reason} ->
            python_module = python_module_for_elixir(library, module)

            python_function = python_function_for_call(library, function)

            add_target(acc, library, python_module, {python_function, :function})
        end
    end
  end

  defp python_function_for_call(library, function) when is_atom(function) do
    function = Atom.to_string(function)
    streaming = library.streaming |> List.wrap() |> Enum.map(&to_string/1)

    function =
      if String.ends_with?(function, "_stream") do
        base_elixir = String.replace_suffix(function, "_stream", "")
        base_python = python_name_for_elixir_name(base_elixir)

        if base_python in streaming do
          base_elixir
        else
          function
        end
      else
        function
      end

    python_name_for_elixir_name(function)
  end

  defp accumulate_includes([], _library, acc), do: acc

  defp accumulate_includes(includes, library, acc) do
    key = {library, library.python_name}
    includes = Enum.map(includes, &{to_string(&1), :unknown})
    Map.update(acc, key, includes, fn funcs -> includes ++ funcs end)
  end

  defp add_target(acc, library, python_module, symbol) do
    key = {library, python_module}
    Map.update(acc, key, [symbol], fn funcs -> [symbol | funcs] end)
  end

  defp library_for_module(config, module) do
    module_parts = Module.split(module)

    Enum.find(config.libraries, fn library ->
      library_parts = Module.split(library.module_name)
      Enum.take(module_parts, length(library_parts)) == library_parts
    end)
  end

  defp build_manifest_entries(
         library,
         python_module,
         infos,
         reserved_modules,
         used_class_modules,
         existing_class_map
       ) do
    filtered = Enum.reject(infos, & &1["error"])
    {class_infos, function_infos} = Enum.split_with(filtered, &(&1["type"] == "class"))

    symbol_entries = Enum.map(function_infos, &symbol_entry_for(library, python_module, &1))

    reserved_modules = add_symbol_modules(symbol_entries, reserved_modules)

    {class_entries, used_class_modules} =
      Enum.reduce(class_infos, {[], used_class_modules}, fn info, {acc, used} ->
        {entry, used} =
          class_entries_for(
            library,
            python_module,
            info,
            reserved_modules,
            used,
            existing_class_map
          )

        {[entry | acc], used}
      end)

    {symbol_entries, class_entries, reserved_modules, used_class_modules}
  end

  defp symbol_entry_for(library, python_module, info) do
    module = module_for_python(library, python_module)
    python_name = info["python_name"] || info["name"]
    {elixir_name, _python_name} = sanitize_function_name(python_name)
    attribute? = info["type"] == "attribute"
    params = info["parameters"] || []
    streaming? = python_name in List.wrap(library.streaming)

    {arity, arity_info} =
      case attribute? do
        true -> {0, module_attr_arity_info()}
        _ -> {required_arity(params), compute_arity_info(params, info)}
      end

    key = Manifest.symbol_key({module, String.to_atom(elixir_name), arity})

    {
      key,
      %{
        "module" => Module.split(module) |> Enum.join("."),
        "function" => python_name,
        "name" => elixir_name,
        "python_name" => python_name,
        "elixir_name" => elixir_name,
        "python_module" => python_module,
        "signature_available" => Map.get(info, "signature_available", true),
        "signature_source" => info["signature_source"],
        "signature_detail" => info["signature_detail"],
        "signature_missing_reason" => info["signature_missing_reason"],
        "doc_source" => info["doc_source"],
        "doc_missing_reason" => info["doc_missing_reason"],
        "overload_count" => info["overload_count"],
        "parameters" => params,
        "docstring" => info["docstring"] || "",
        "return_annotation" => info["return_annotation"],
        "return_type" => info["return_type"],
        "streaming" => streaming?
      }
      |> Map.merge(arity_info)
      |> maybe_put_call_type(attribute?)
    }
  end

  defp maybe_put_call_type(entry, true), do: Map.put(entry, "call_type", "module_attr")
  defp maybe_put_call_type(entry, _attribute?), do: entry

  defp module_attr_arity_info do
    %{
      "required_arity" => 0,
      "minimum_arity" => 0,
      "maximum_arity" => 0,
      "has_var_positional" => false,
      "has_var_keyword" => false,
      "required_keyword_only" => [],
      "optional_keyword_only" => []
    }
  end

  defp class_entries_for(
         library,
         python_module,
         info,
         reserved_modules,
         used_class_modules,
         existing_class_map
       ) do
    class_name = class_name_from_info(info)
    class_python_module = class_python_module_from_info(info, python_module, library)
    class_key = {class_python_module, class_name}

    preferred_module = Map.get(existing_class_map, class_key)

    class_module =
      class_module_for_preference(preferred_module, library, class_python_module, class_name)

    used_class_modules = drop_preferred_class_module(used_class_modules, preferred_module)

    {class_module, used_class_modules} =
      unique_class_module(class_module, reserved_modules, used_class_modules)

    key = Manifest.class_key(class_module)

    methods =
      info["methods"]
      |> List.wrap()
      |> Enum.map(&class_method_entry/1)
      |> Enum.reject(&is_nil/1)

    {
      {
        key,
        %{
          "module" => Module.split(class_module) |> Enum.join("."),
          "class" => class_name,
          "python_module" => class_python_module,
          "docstring" => info["docstring"] || "",
          "doc_source" => info["doc_source"],
          "doc_missing_reason" => info["doc_missing_reason"],
          "methods" => methods,
          "attributes" => info["attributes"] || [],
          "methods_truncated" => info["methods_truncated"] == true,
          "method_scope" => info["method_scope"]
        }
      },
      used_class_modules
    }
  end

  defp class_name_from_info(info) do
    info["name"] || info["class"] || "Class"
  end

  defp class_python_module_from_info(info, python_module, library) do
    info["python_module"] || python_module || library.python_name
  end

  defp class_module_for_preference(nil, library, class_python_module, class_name) do
    class_module_for(library, class_python_module, class_name)
  end

  defp class_module_for_preference(preferred_module, _library, _class_python_module, _class_name),
    do: preferred_module

  defp drop_preferred_class_module(used_class_modules, nil), do: used_class_modules

  defp drop_preferred_class_module(used_class_modules, preferred_module) do
    MapSet.delete(used_class_modules, preferred_module)
  end

  defp class_method_entry(method) do
    name = method_value(method, :name, "")

    case Generator.sanitize_method_name(name) do
      {elixir_name, python_name} ->
        params = method_value(method, :parameters, [])
        arity_info = method_arity_info(params, method, python_name)

        method
        |> Map.put("name", python_name)
        |> Map.put("python_name", python_name)
        |> Map.put("elixir_name", elixir_name)
        |> Map.put("signature_source", method_value(method, :signature_source))
        |> Map.put("signature_detail", method_value(method, :signature_detail))
        |> Map.put("signature_missing_reason", method_value(method, :signature_missing_reason))
        |> Map.put("doc_source", method_value(method, :doc_source))
        |> Map.put("doc_missing_reason", method_value(method, :doc_missing_reason))
        |> Map.put("overload_count", method_value(method, :overload_count))
        |> Map.merge(arity_info)

      nil ->
        nil
    end
  end

  defp method_value(method, key, default \\ nil) do
    Map.get(method, Atom.to_string(key)) || Map.get(method, key) || default
  end

  defp method_arity_info(params, method, python_name) do
    arity_info = compute_arity_info(params, method)

    case python_name do
      "__init__" -> arity_info
      _ -> add_ref_arity_info(arity_info)
    end
  end

  defp add_ref_arity_info(arity_info) do
    min_arity = Map.get(arity_info, "minimum_arity", 0) + 1
    required_arity = Map.get(arity_info, "required_arity", 0) + 1
    max_arity = Map.get(arity_info, "maximum_arity")

    max_arity =
      case max_arity do
        value when is_integer(value) -> value + 1
        _ -> max_arity
      end

    arity_info
    |> Map.put("minimum_arity", min_arity)
    |> Map.put("required_arity", required_arity)
    |> Map.put("maximum_arity", max_arity)
  end

  defp class_module_for(library, python_module, class_name) do
    python_parts = String.split(python_module, ".")
    library_parts = String.split(library.python_name, ".")
    extra_parts = Enum.drop(python_parts, length(library_parts))
    extra_parts = drop_class_suffix(extra_parts, class_name)
    class_segment = Macro.camelize(class_name)

    library.module_name
    |> Module.split()
    |> Kernel.++(Enum.map(extra_parts, &Macro.camelize/1))
    |> Kernel.++([class_segment])
    |> Module.concat()
  end

  defp drop_class_suffix(parts, class_name) when is_list(parts) and is_binary(class_name) do
    class_suffix = Macro.underscore(class_name)

    case List.last(parts) do
      ^class_suffix -> Enum.drop(parts, -1)
      _ -> parts
    end
  end

  defp drop_class_suffix(parts, _class_name), do: parts

  defp module_for_python(library, python_module) do
    python_parts = String.split(python_module, ".")
    library_parts = String.split(library.python_name, ".")
    extra_parts = Enum.drop(python_parts, length(library_parts))

    library.module_name
    |> Module.split()
    |> Kernel.++(Enum.map(extra_parts, &Macro.camelize/1))
    |> Module.concat()
  end

  defp unique_class_module(class_module, reserved_modules, used_class_modules) do
    # Class module names should take precedence over module wrapper names.
    # Module wrappers can be disambiguated at generation time by appending `.Module`.
    case MapSet.member?(used_class_modules, class_module) do
      true ->
        parts = Module.split(class_module)
        {base_parts, [last]} = Enum.split(parts, -1)

        unique =
          disambiguate_class_module(base_parts, last, reserved_modules, used_class_modules, 2)

        {unique, MapSet.put(used_class_modules, unique)}

      _ ->
        {class_module, MapSet.put(used_class_modules, class_module)}
    end
  end

  defp disambiguate_class_module(base_parts, last, reserved_modules, used_class_modules, counter) do
    suffix =
      case counter do
        2 -> "Class"
        _ -> "Class" <> Integer.to_string(counter)
      end

    candidate = Module.concat(base_parts ++ [last <> suffix])

    case MapSet.member?(reserved_modules, candidate) or
           MapSet.member?(used_class_modules, candidate) do
      true ->
        disambiguate_class_module(
          base_parts,
          last,
          reserved_modules,
          used_class_modules,
          counter + 1
        )

      _ ->
        candidate
    end
  end

  defp reserved_modules_from_manifest(manifest) do
    manifest
    |> Map.get("symbols", %{})
    |> Map.values()
    |> Enum.reduce(MapSet.new(), fn info, acc ->
      case info["module"] do
        module when is_binary(module) -> MapSet.put(acc, module_from_string(module))
        _ -> acc
      end
    end)
  end

  defp existing_classes_from_manifest(manifest) do
    manifest
    |> Map.get("classes", %{})
    |> Enum.reduce({%{}, MapSet.new()}, fn {module, info}, {map, set} ->
      python_module = info["python_module"] || info[:python_module]
      class_name = info["class"] || info["name"] || info[:class] || info[:name]

      case {python_module, class_name, module} do
        {python_module, class_name, module}
        when is_binary(python_module) and is_binary(class_name) and is_binary(module) ->
          module_atom = module_from_string(module)
          {Map.put(map, {python_module, class_name}, module_atom), MapSet.put(set, module_atom)}

        _ ->
          {map, set}
      end
    end)
  end

  defp reserved_modules_from_namespaces(library, namespaces) do
    Enum.reduce(namespaces, MapSet.new(), fn {namespace, data}, acc ->
      python_module =
        case namespace do
          "" -> library.python_name
          _ -> "#{library.python_name}.#{namespace}"
        end

      functions = data["functions"] || []
      attributes = data["attributes"] || []

      visible =
        (functions ++ attributes)
        |> Enum.reject(fn info -> info["name"] in library.exclude end)

      case visible do
        [] -> acc
        _ -> MapSet.put(acc, module_for_python(library, python_module))
      end
    end)
  end

  defp add_symbol_modules(symbol_entries, reserved_modules) do
    Enum.reduce(symbol_entries, reserved_modules, fn {_key, info}, acc ->
      case info["module"] do
        module when is_binary(module) -> MapSet.put(acc, module_from_string(module))
        _ -> acc
      end
    end)
  end

  defp class_keys_from_infos(infos, python_module) do
    infos
    |> Enum.filter(&(&1["type"] == "class"))
    |> Enum.map(&class_key_from_info(&1, python_module))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp class_keys_from_classes(classes, python_module) do
    classes
    |> Enum.map(&class_key_from_info(&1, python_module))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp class_key_from_info(info, python_module) do
    class_name = info["name"] || info["class"]
    class_python_module = info["python_module"] || python_module

    case {class_python_module, class_name} do
      {class_python_module, class_name}
      when is_binary(class_python_module) and is_binary(class_name) ->
        {class_python_module, class_name}

      _ ->
        nil
    end
  end

  defp drop_class_entries(manifest, class_keys) do
    case MapSet.size(class_keys) do
      0 ->
        manifest

      _ ->
        classes =
          manifest
          |> Map.get("classes", %{})
          |> Enum.reject(fn {_module, info} ->
            key = class_key_from_info(info, info["python_module"] || info[:python_module])
            key in class_keys
          end)
          |> Map.new()

        Map.put(manifest, "classes", classes)
    end
  end

  defp clear_library_classes(manifest, library) do
    classes =
      manifest
      |> Map.get("classes", %{})
      |> Enum.reject(fn {_module, info} ->
        python_module = info["python_module"] || ""
        String.starts_with?(python_module, library.python_name)
      end)
      |> Map.new()

    symbols =
      manifest
      |> Map.get("symbols", %{})
      |> Enum.reject(fn {_key, info} ->
        python_module = info["python_module"] || ""
        String.starts_with?(python_module, library.python_name)
      end)
      |> Map.new()

    modules =
      manifest
      |> Map.get("modules", %{})
      |> Enum.reject(fn {python_module, info} ->
        python_module = to_string(python_module || info["python_module"] || "")
        String.starts_with?(python_module, library.python_name)
      end)
      |> Map.new()

    manifest
    |> Map.put("classes", classes)
    |> Map.put("symbols", symbols)
    |> Map.put("modules", modules)
  end

  defp module_from_string(module) when is_binary(module) do
    module
    |> String.split(".")
    |> Module.concat()
  end

  defp python_module_for_elixir(library, module) do
    module_parts = Module.split(module)
    library_parts = Module.split(library.module_name)
    extra_parts = Enum.drop(module_parts, length(library_parts))

    case Enum.map(extra_parts, &Macro.underscore/1) do
      [] -> library.python_name
      parts -> library.python_name <> "." <> Enum.join(parts, ".")
    end
  end

  defp function_or_class_present?(manifest, library, name) do
    module_prefix = Module.split(library.module_name) |> Enum.join(".")

    function_present_in_manifest?(manifest, module_prefix, name) or
      class_present_in_manifest?(manifest, name)
  end

  defp function_present_in_manifest?(manifest, module_prefix, name) do
    manifest
    |> Map.get("symbols", %{})
    |> Map.values()
    |> Enum.any?(&symbol_matches?(&1, module_prefix, name))
  end

  defp symbol_matches?(info, module_prefix, name) do
    module = info["module"] || ""
    python_name = info["python_name"] || info["function"] || info["name"]
    elixir_name = info["elixir_name"] || info["name"] || python_name
    module == module_prefix and (python_name == name or elixir_name == name)
  end

  defp class_present_in_manifest?(manifest, name) do
    manifest
    |> Map.get("classes", %{})
    |> Map.values()
    |> Enum.any?(&class_matches?(&1, name))
  end

  defp class_matches?(info, name) do
    info["class"] == name or String.ends_with?(info["module"] || "", ".#{name}")
  end

  defp generate_from_manifest(config, manifest, lock_data) do
    module_docs = Map.get(manifest, "modules", %{})

    Enum.each(config.libraries, fn library ->
      functions = functions_for_library(manifest, library)
      classes = classes_for_library(manifest, library)
      Generator.generate_library(library, functions, classes, config, module_docs, lock_data)
    end)
  end

  defp functions_for_library(manifest, library) do
    Map.get(manifest, "symbols", %{})
    |> Map.values()
    |> Enum.filter(fn info ->
      python_module = info["python_module"] || ""
      String.starts_with?(python_module, library.python_name)
    end)
  end

  defp classes_for_library(manifest, library) do
    Map.get(manifest, "classes", %{})
    |> Map.values()
    |> Enum.filter(fn info ->
      python_module = info["python_module"] || ""
      String.starts_with?(python_module, library.python_name)
    end)
  end

  defp strict_mode?(config) do
    System.get_env("SNAKEBRIDGE_STRICT") == "1" || config.strict == true
  end

  defp run_strict(config) do
    _ = SnakeBridge.Registry.load()
    manifest = Manifest.load(config)
    detected = scanner_module().scan_project(config)
    missing = Manifest.missing(manifest, detected)

    case missing do
      [] ->
        :ok

      _ ->
        formatted = format_missing(missing)

        raise SnakeBridge.CompileError, """
        Strict mode: #{length(missing)} symbol(s) not in manifest.

        Missing:
        #{formatted}

        To fix:
          1. Run `mix snakebridge.setup` locally
          2. Run `mix compile` to generate bindings
          3. Commit the updated manifest and generated files
          4. Re-run CI

        Set SNAKEBRIDGE_STRICT=0 to disable strict mode.
        """
    end

    verify_generated_files_exist!(config, manifest)
    verify_symbols_present!(config, manifest)

    {:ok, []}
  end

  defp run_normal(config) do
    start_time = System.monotonic_time()
    libraries = Enum.map(config.libraries, & &1.name)
    Telemetry.compile_start(libraries, false)

    try do
      _ = SnakeBridge.Registry.load()
      manifest = Manifest.load(config)

      # First, handle libraries with generate: :all
      {all_libraries, used_libraries} =
        Enum.split_with(config.libraries, &(&1.generate == :all))

      {manifest, generate_all_errors} = process_generate_all_libraries(manifest, all_libraries)

      # Then handle libraries with generate: :used (default)
      used_config = %{config | libraries: used_libraries}
      detected = scanner_module().scan_project(used_config)
      missing = Manifest.missing(manifest, detected)
      targets = build_targets(missing, used_config, manifest)

      {updated_manifest, introspection_errors} =
        case targets do
          [] -> {manifest, []}
          _ -> update_manifest(manifest, targets)
        end

      {updated_manifest, unresolved_missing} =
        apply_truncated_class_method_stubs(updated_manifest, detected, used_config)

      errors = generate_all_errors ++ format_introspection_errors(introspection_errors)

      updated_manifest = update_manifest_module_docs(updated_manifest, config)
      Manifest.save(config, updated_manifest)
      enforce_signature_thresholds!(config, updated_manifest)

      lock_data = Lock.build(config)
      generate_from_manifest(config, updated_manifest, lock_data)
      generate_helper_wrappers(config)
      SnakeBridge.Registry.save()
      Lock.write(lock_data)
      SnakeBridge.CoverageReport.write_reports(config, updated_manifest, errors)

      case unresolved_missing do
        [] ->
          :ok

        _ ->
          formatted = format_missing(unresolved_missing)

          raise SnakeBridge.CompileError, """
          SnakeBridge could not generate bindings for #{length(unresolved_missing)} call(s).

          Missing:
          #{formatted}

          This usually means:
            - the Python symbol does not exist in the installed version, or
            - the call arity does not match the Python signature, or
            - generation is intentionally restricted (e.g. class method guardrails).

          Fix by:
            - updating your Python dependency versions, or
            - adjusting SnakeBridge library options (include/exclude, class_method_scope/max_class_methods), or
            - using SnakeBridge.Dynamic as an escape hatch for runtime-only calls.
          """
      end

      symbol_count = count_symbols(updated_manifest)
      file_count = length(config.libraries)
      Telemetry.compile_stop(start_time, symbol_count, file_count, libraries, :normal)
      {:ok, []}
    rescue
      e ->
        Telemetry.compile_exception(start_time, e, __STACKTRACE__)
        reraise e, __STACKTRACE__
    end
  end

  defp with_introspector_config(config, fun) do
    original = Application.get_env(:snakebridge, :introspector, [])
    merged = merge_introspector_config(original, List.wrap(config.introspector))
    Application.put_env(:snakebridge, :introspector, merged)

    try do
      fun.()
    after
      Application.put_env(:snakebridge, :introspector, original)
    end
  end

  defp merge_introspector_config(base, override) do
    base = List.wrap(base)
    override = List.wrap(override)

    Keyword.merge(base, override, fn
      :env, base_env, override_env ->
        Map.merge(Map.new(base_env || %{}), Map.new(override_env || %{}))

      _key, _base, override_value ->
        override_value
    end)
  end

  defp process_generate_all_libraries(manifest, []), do: {manifest, []}

  defp process_generate_all_libraries(manifest, libraries) do
    Enum.reduce(libraries, {manifest, []}, fn library, {acc, errors} ->
      {updated, library_errors} = process_generate_all_library(acc, library)
      {updated, errors ++ library_errors}
    end)
  end

  defp process_generate_all_library(manifest, library) do
    case library.module_mode do
      :docs -> process_generate_docs_library(manifest, library)
      _ -> process_generate_all_library_introspect(manifest, library)
    end
  end

  defp process_generate_all_library_introspect(manifest, library) do
    {opts, submodule_msg} = submodule_opts_and_msg(library)

    Mix.shell().info("[SnakeBridge] Introspecting #{library.python_name}#{submodule_msg}...")

    case SnakeBridge.Introspector.introspect_module(library, opts) do
      {:ok, result} ->
        class_count = count_classes_in_result(result)
        Mix.shell().info("[SnakeBridge] Found #{class_count} classes to generate")
        update_manifest_from_module_introspection(manifest, library, result)

      {:error, reason} ->
        {manifest, [generate_all_error(library, reason)]}
    end
  end

  defp submodule_opts_and_msg(library) do
    submodules = normalize_submodules_list(library.submodules)
    opts = submodules_opts(submodules)
    msg = submodules_msg(library.submodules)
    {opts, msg}
  end

  defp normalize_submodules_list(list) when is_list(list) and list != [], do: list
  defp normalize_submodules_list(_), do: nil

  defp submodules_opts(nil), do: []
  defp submodules_opts(list), do: [submodules: list]

  defp submodules_msg(true), do: " with submodules"
  defp submodules_msg(_), do: ""

  defp process_generate_docs_library(manifest, library) do
    case Docs.Manifest.load_profile(library) do
      {:ok, %{modules: modules, objects: objects}} ->
        Mix.shell().info(
          "[SnakeBridge] Docs manifest for #{library.python_name}: #{length(objects)} objects across #{length(modules)} modules"
        )

        manifest = clear_library_classes(manifest, library)
        {targets, placeholder_modules} = docs_manifest_targets(library, objects, modules)

        placeholders =
          placeholder_modules
          |> Enum.map(fn python_module ->
            module_entry(
              python_module,
              "",
              nil,
              "docs_manifest",
              "module included by docs manifest (no objects selected)"
            )
          end)

        manifest =
          case placeholders do
            [] -> manifest
            _ -> Manifest.put_modules(manifest, placeholders)
          end

        {updated_manifest, introspection_errors} =
          case targets do
            [] -> {manifest, []}
            _ -> update_manifest(manifest, targets)
          end

        {updated_manifest, format_introspection_errors(introspection_errors)}

      {:error, reason} ->
        {manifest, [generate_all_error(library, reason)]}
    end
  end

  defp docs_manifest_targets(library, objects, modules) do
    objects_by_module =
      objects
      |> Enum.flat_map(&object_symbol_ref(&1, library))
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {python_module, symbols} ->
        symbols =
          symbols
          |> Enum.reduce(%{}, fn {symbol, kind}, acc ->
            Map.update(acc, symbol, kind, &preferred_kind(&1, kind))
          end)
          |> Enum.map(fn {symbol, kind} -> {symbol, kind} end)
          |> Enum.sort_by(&elem(&1, 0))

        {python_module, symbols}
      end)
      |> Map.new()

    targets =
      objects_by_module
      |> Enum.sort_by(fn {python_module, symbols} ->
        root_priority =
          case python_module == library.python_name do
            true -> 0
            _ -> 1
          end

        module_depth = length(String.split(python_module, "."))
        {root_priority, module_depth, python_module, length(symbols)}
      end)
      |> Enum.map(fn {python_module, symbols} -> {library, python_module, symbols} end)

    placeholder_modules =
      modules
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in Map.keys(objects_by_module)))

    {targets, placeholder_modules}
  end

  defp object_symbol_ref(object, library) do
    with {name, kind} <- object_name_and_kind(object),
         {:ok, python_module, symbol} <- split_object_name(name) do
      python_module =
        case String.starts_with?(python_module, library.python_name) do
          true -> python_module
          _ -> library.python_name <> "." <> python_module
        end

      [{python_module, {symbol, kind}}]
    else
      _ -> []
    end
  end

  defp object_name_and_kind(%{name: name, kind: kind}) when is_binary(name),
    do: {name, kind}

  defp object_name_and_kind(%{name: name}) when is_binary(name),
    do: {name, :unknown}

  defp object_name_and_kind(name) when is_binary(name),
    do: {name, :unknown}

  defp object_name_and_kind(_),
    do: :error

  defp split_object_name(name) when is_binary(name) do
    parts = String.split(name, ".")

    case parts do
      [_single] ->
        :error

      _ ->
        symbol = List.last(parts)
        python_module = parts |> Enum.drop(-1) |> Enum.join(".")

        case {python_module, symbol} do
          {"", _} -> :error
          {_, ""} -> :error
          _ -> {:ok, python_module, symbol}
        end
    end
  end

  defp count_classes_in_result(%{"namespaces" => namespaces}) do
    Enum.reduce(namespaces, 0, fn {_namespace, data}, acc ->
      acc + length(data["classes"] || [])
    end)
  end

  defp count_classes_in_result(_), do: 0

  defp update_manifest_from_module_introspection(
         manifest,
         library,
         %{"namespaces" => namespaces} = result
       ) do
    base_issues = extract_module_issues(library, result)

    # Clear all existing classes for this library before adding new ones
    # This is important for public_api filtering - we don't want stale classes
    manifest = clear_library_classes(manifest, library)

    {existing_class_map, existing_class_modules} = existing_classes_from_manifest(manifest)

    reserved_modules =
      manifest
      |> reserved_modules_from_manifest()
      |> MapSet.union(reserved_modules_from_namespaces(library, namespaces))

    {updated, issues, _used_class_modules} =
      Enum.reduce(
        namespaces,
        {manifest, base_issues, existing_class_modules},
        fn {namespace, data}, {acc, issues_acc, used_class_modules} ->
          python_module =
            case namespace do
              "" -> library.python_name
              _ -> "#{library.python_name}.#{namespace}"
            end

          functions = data["functions"] || []
          classes = data["classes"] || []
          attributes = data["attributes"] || []

          filtered_functions =
            functions
            |> Enum.reject(fn info -> info["name"] in library.exclude end)

          filtered_attributes =
            attributes
            |> Enum.reject(fn info -> info["name"] in library.exclude end)

          # Build entries for functions and attributes
          {symbol_entries, _} =
            (filtered_functions ++ filtered_attributes)
            |> Enum.reduce({[], []}, fn info, {symbols, classes_acc} ->
              info = Map.put(info, "python_module", python_module)
              entry = symbol_entry_for(library, python_module, info)
              {[entry | symbols], classes_acc}
            end)

          # Build entries for classes
          visible_classes =
            classes
            |> Enum.reject(fn info -> info["name"] in library.exclude end)

          class_keys = class_keys_from_classes(visible_classes, python_module)

          {class_entries, used_class_modules} =
            visible_classes
            |> Enum.reduce({[], used_class_modules}, fn info, {acc_entries, used} ->
              info = Map.put(info, "python_module", python_module)

              {entry, used} =
                class_entries_for(
                  library,
                  python_module,
                  info,
                  reserved_modules,
                  used,
                  existing_class_map
                )

              {[entry | acc_entries], used}
            end)

          updated =
            acc
            |> drop_class_entries(class_keys)
            |> Manifest.put_symbols(symbol_entries)
            |> Manifest.put_classes(class_entries)

          issues = issues_acc ++ extract_namespace_issues(library, python_module, data)
          {updated, issues, used_class_modules}
        end
      )

    module_entries = module_entries_from_module_introspection(library, result)
    updated = Manifest.put_modules(updated, module_entries)

    {updated, issues}
  end

  defp update_manifest_from_module_introspection(
         manifest,
         library,
         %{"functions" => functions, "classes" => classes} = data
       ) do
    # Flat format (v2.0)
    python_module = library.python_name
    attributes = data["attributes"] || []

    # Clear all existing classes for this library before adding new ones
    manifest = clear_library_classes(manifest, library)

    {existing_class_map, existing_class_modules} = existing_classes_from_manifest(manifest)
    reserved_modules = reserved_modules_from_manifest(manifest)

    filtered_functions =
      functions
      |> Enum.reject(fn info -> info["name"] in library.exclude end)

    filtered_attributes =
      attributes
      |> Enum.reject(fn info -> info["name"] in library.exclude end)

    {symbol_entries, _} =
      (filtered_functions ++ filtered_attributes)
      |> Enum.reduce({[], []}, fn info, {symbols, classes_acc} ->
        info = Map.put(info, "python_module", python_module)
        entry = symbol_entry_for(library, python_module, info)
        {[entry | symbols], classes_acc}
      end)

    reserved_modules = add_symbol_modules(symbol_entries, reserved_modules)

    visible_classes =
      classes
      |> Enum.reject(fn info -> info["name"] in library.exclude end)

    class_keys = class_keys_from_classes(visible_classes, python_module)

    {class_entries, _used_class_modules} =
      visible_classes
      |> Enum.reduce({[], existing_class_modules}, fn info, {acc_entries, used} ->
        info = Map.put(info, "python_module", python_module)

        {entry, used} =
          class_entries_for(
            library,
            python_module,
            info,
            reserved_modules,
            used,
            existing_class_map
          )

        {[entry | acc_entries], used}
      end)

    updated =
      manifest
      |> drop_class_entries(class_keys)
      |> Manifest.put_symbols(symbol_entries)
      |> Manifest.put_classes(class_entries)

    issues =
      extract_module_issues(library, data) ++
        extract_namespace_issues(library, python_module, data)

    module_entries = module_entries_from_module_introspection(library, data)
    updated = Manifest.put_modules(updated, module_entries)

    {updated, issues}
  end

  defp update_manifest_from_module_introspection(manifest, _library, _result), do: {manifest, []}

  defp update_manifest_module_docs(manifest, config) do
    modules = modules_from_manifest(manifest, config)
    existing = Map.get(manifest, "modules", %{})
    missing = Enum.reject(modules, &Map.has_key?(existing, &1))

    case missing do
      [] ->
        manifest

      _ ->
        entries = module_doc_entries(missing, config)
        Manifest.put_modules(manifest, entries)
    end
  end

  defp module_entries_from_module_introspection(
         library,
         %{"namespaces" => namespaces} = result
       ) do
    namespace_entries =
      namespaces
      |> Enum.map(fn {namespace, data} ->
        python_module =
          case namespace do
            "" -> library.python_name
            _ -> "#{library.python_name}.#{namespace}"
          end

        module_entry_from_doc_info(python_module, data)
      end)

    root_entry = module_entry_from_doc_info(library.python_name, result, result["module_version"])

    [root_entry | namespace_entries]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn {python_module, _} -> python_module end)
  end

  defp module_entries_from_module_introspection(library, result) when is_map(result) do
    root_entry = module_entry_from_doc_info(library.python_name, result, result["module_version"])
    [root_entry]
  end

  defp module_doc_entries(missing, config) do
    missing
    |> Enum.group_by(&library_for_python_module(config.libraries, &1))
    |> Enum.flat_map(&fetch_module_doc_entries/1)
  end

  defp fetch_module_doc_entries({nil, _modules}), do: []

  defp fetch_module_doc_entries({library, modules}) do
    case SnakeBridge.Introspector.introspect_module_docs(library, modules) do
      {:ok, infos} ->
        infos
        |> Enum.map(&module_entry_from_introspector_info/1)
        |> Enum.reject(&is_nil/1)

      {:error, reason} ->
        build_error_module_entries(modules, reason)
    end
  end

  defp build_error_module_entries(modules, reason) do
    Enum.map(modules, fn python_module ->
      module_entry(python_module, "", nil, "error", module_doc_error(reason))
    end)
  end

  defp module_entry_from_introspector_info(info) when is_map(info) do
    python_module = info["module"] || info["python_module"]
    module_entry_from_doc_info(python_module, info, info["module_version"])
  end

  defp module_entry_from_doc_info(python_module, info, module_version_override \\ nil)
       when is_binary(python_module) do
    docstring = info["docstring"] || ""
    doc_source = info["doc_source"]
    doc_missing_reason = info["doc_missing_reason"]
    module_version = module_version_override || info["module_version"]
    error = info["error"]

    {doc_source, doc_missing_reason} =
      case error && docstring in [nil, ""] do
        true -> {"error", error}
        _ -> {doc_source, doc_missing_reason}
      end

    module_entry(
      python_module,
      docstring,
      module_version,
      doc_source,
      doc_missing_reason
    )
  end

  defp module_entry(python_module, docstring, module_version, doc_source, doc_missing_reason) do
    {doc_source, doc_missing_reason} =
      module_doc_source(docstring, doc_source, doc_missing_reason)

    entry = %{
      "python_module" => python_module,
      "docstring" => docstring || "",
      "doc_source" => doc_source,
      "doc_missing_reason" => doc_missing_reason
    }

    entry =
      case module_version do
        nil -> entry
        _ -> Map.put(entry, "module_version", module_version)
      end

    {python_module, entry}
  end

  defp module_doc_source(_docstring, doc_source, doc_missing_reason) when is_binary(doc_source) do
    {doc_source, doc_missing_reason}
  end

  defp module_doc_source(docstring, _doc_source, doc_missing_reason) do
    case docstring in [nil, ""] do
      true -> {"empty", doc_missing_reason || "docstring missing"}
      _ -> {"runtime", doc_missing_reason}
    end
  end

  defp module_doc_error(reason) when is_binary(reason), do: reason

  defp module_doc_error(reason) when is_map(reason) do
    Map.get(reason, "message") || inspect(reason)
  end

  defp module_doc_error(reason), do: inspect(reason)

  defp modules_from_manifest(manifest, config) do
    library_roots = Enum.map(config.libraries, & &1.python_name)

    symbol_modules =
      manifest
      |> Map.get("symbols", %{})
      |> Map.values()
      |> Enum.map(&(&1["python_module"] || ""))

    class_modules =
      manifest
      |> Map.get("classes", %{})
      |> Map.values()
      |> Enum.map(&(&1["python_module"] || ""))

    (library_roots ++ symbol_modules ++ class_modules)
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp library_for_python_module(libraries, python_module) when is_binary(python_module) do
    libraries
    |> Enum.filter(fn library ->
      String.starts_with?(python_module, library.python_name)
    end)
    |> Enum.max_by(fn library -> String.length(library.python_name) end, fn -> nil end)
  end

  defp generate_all_error(library, reason) do
    %{
      type: :introspect_module_failed,
      library: library.name,
      python_module: library.python_name,
      reason: reason
    }
  end

  defp extract_module_issues(library, result) do
    issues = Map.get(result, "issues", []) || []

    Enum.map(issues, fn issue ->
      %{
        type: :introspection_issue,
        library: library.name,
        python_module: issue["module"] || library.python_name,
        reason: issue
      }
    end)
  end

  defp extract_namespace_issues(library, python_module, data) do
    issues = Map.get(data, "issues", []) || []

    Enum.map(issues, fn issue ->
      %{
        type: :introspection_issue,
        library: library.name,
        python_module: python_module,
        reason: issue
      }
    end)
  end

  # Test helper - exposes process_generate_all_library for testing
  @doc false
  def test_process_generate_all_library(manifest, library) do
    {updated, _errors} = process_generate_all_library(manifest, library)
    updated
  end

  @doc false
  @spec test_class_module_for(term(), String.t(), String.t(), MapSet.t(), MapSet.t()) :: module()
  def test_class_module_for(
        library,
        python_module,
        class_name,
        reserved_modules,
        used_class_modules
      ) do
    class_module = class_module_for(library, python_module, class_name)

    {class_module, _used_class_modules} =
      unique_class_module(class_module, reserved_modules, used_class_modules)

    class_module
  end

  defp enforce_signature_thresholds!(config, manifest) do
    SnakeBridge.SignatureThresholds.enforce!(config, manifest)
  end

  defp format_introspection_errors(errors) do
    Enum.map(errors, fn {library, python_module, reason} ->
      %{
        type: :introspection_failed,
        library: library_name(library),
        python_module: python_module,
        reason: reason
      }
    end)
  end

  defp library_name(%{name: name}) when is_atom(name), do: name
  defp library_name(name) when is_atom(name), do: name
  defp library_name(%{python_name: name}) when is_binary(name), do: name
  defp library_name(name) when is_binary(name), do: name
  defp library_name(_), do: :unknown

  @spec verify_generated_files_exist!(Config.t(), map() | nil) :: :ok
  def verify_generated_files_exist!(config, manifest \\ nil) do
    Enum.each(config.libraries, fn library ->
      paths = generated_paths_for_library(config, library, manifest)
      missing = Enum.reject(paths, &File.exists?/1)

      case missing do
        [] ->
          :ok

        _ ->
          raise SnakeBridge.CompileError, """
          Strict mode: Generated files missing for #{library.python_name}:
          #{format_missing_files(missing)}

          Run `mix compile` locally and commit the generated files.
          """
      end
    end)

    :ok
  end

  @spec verify_symbols_present!(Config.t(), map()) :: :ok
  def verify_symbols_present!(config, manifest) do
    Enum.each(config.libraries, fn library ->
      paths = generated_paths_for_library(config, library, manifest)
      defs = parse_definitions_from_paths!(paths)

      missing_functions = missing_functions_for_library(manifest, library, defs)
      classes_for_library = classes_for_library(manifest, library)
      missing_classes = missing_classes_for_library(classes_for_library, defs)
      missing_class_members = missing_class_members_for_library(classes_for_library, defs)

      maybe_raise_missing!(paths, missing_functions, missing_classes, missing_class_members)
    end)

    :ok
  end

  defp missing_functions_for_library(manifest, library, defs) do
    manifest
    |> functions_for_library(library)
    |> Enum.reject(fn info ->
      function_defined?(defs, info["module"], info["name"])
    end)
  end

  defp missing_classes_for_library(classes_for_library, defs) do
    Enum.reject(classes_for_library, fn info ->
      module = info["module"]
      Map.has_key?(defs, module)
    end)
  end

  defp missing_class_members_for_library(classes_for_library, defs) do
    classes_for_library
    |> Enum.filter(fn info -> Map.has_key?(defs, info["module"]) end)
    |> Enum.flat_map(&missing_members_for_class(&1, defs))
  end

  defp missing_members_for_class(info, defs) do
    module = info["module"]
    method_names = missing_method_names(info["methods"] || [], defs, module)
    attr_names = missing_attr_names(info["attributes"] || [], defs, module)

    Enum.map(method_names ++ attr_names, fn name ->
      {module, name}
    end)
  end

  defp missing_method_names(methods, defs, module) do
    methods
    |> Enum.map(&method_expected_name/1)
    |> Enum.reject(fn name ->
      name == "" or function_defined?(defs, module, name)
    end)
  end

  defp missing_attr_names(attrs, defs, module) do
    attrs
    |> Enum.map(&to_string/1)
    |> Enum.reject(fn name ->
      name == "" or function_defined?(defs, module, name)
    end)
  end

  defp maybe_raise_missing!(paths, missing_functions, missing_classes, missing_class_members) do
    case {missing_functions, missing_classes, missing_class_members} do
      {[], [], []} ->
        :ok

      _ ->
        raise SnakeBridge.CompileError, """
        Strict mode: Generated files are missing expected bindings.

        Files checked:
        #{format_missing_files(paths)}

        #{missing_functions_message(missing_functions)}\
        #{missing_classes_message(missing_classes)}\
        #{missing_class_members_message(missing_class_members)}
        Run `mix compile` locally to regenerate and commit the updated files.
        """
    end
  end

  defp generated_paths_for_library(config, library, manifest) do
    layout = config.generated_layout || :split

    case layout do
      :single -> single_layout_paths(config, library)
      :split -> split_layout_paths(config, library, manifest)
      _ -> split_layout_paths(config, library, manifest)
    end
  end

  defp single_layout_paths(config, library) do
    [Path.join(config.generated_dir, "#{library.python_name}.ex")]
  end

  defp split_layout_paths(config, library, %{} = manifest) do
    functions = functions_for_library(manifest, library)
    classes = classes_for_library(manifest, library)

    function_modules =
      functions
      |> Enum.map(&(&1["python_module"] || library.python_name))
      |> Enum.uniq()

    class_modules =
      classes
      |> Enum.map(&(&1["python_module"] || library.python_name))
      |> Enum.uniq()

    module_modules =
      [library.python_name | function_modules ++ class_modules]
      |> Enum.uniq()
      |> Enum.sort()

    module_paths = Enum.map(module_modules, &PathMapper.module_to_path(&1, config.generated_dir))

    class_paths =
      classes
      |> Enum.map(fn info ->
        python_module = info["python_module"] || library.python_name
        class_name = info["class"] || info["name"] || "Class"
        PathMapper.class_file_path(python_module, class_name, config.generated_dir)
      end)

    Enum.uniq(module_paths ++ class_paths)
  end

  defp split_layout_paths(config, library, _manifest) do
    registry_or_layout_paths(config, library)
  end

  defp registry_or_layout_paths(config, library) do
    case SnakeBridge.Registry.get(library.python_name) do
      %{path: base, files: files} when is_list(files) and files != [] ->
        resolve_registry_paths(base, files, config, library)

      _ ->
        fallback_layout_paths(config, library)
    end
  end

  defp resolve_registry_paths(base, files, config, library) do
    base = Path.expand(base)
    config_base = Path.expand(config.generated_dir)

    case base == config_base do
      true -> Enum.map(files, &Path.join(base, &1))
      _ -> fallback_layout_paths(config, library)
    end
  end

  defp fallback_layout_paths(config, library) do
    layout = config.generated_layout || :split

    case layout do
      :single -> single_layout_paths(config, library)
      :split -> [PathMapper.module_to_path(library.python_name, config.generated_dir)]
      _ -> [PathMapper.module_to_path(library.python_name, config.generated_dir)]
    end
  end

  defp parse_definitions_from_paths!(paths) do
    Enum.reduce(paths, %{}, fn path, acc ->
      content = read_generated_file!(path)
      defs = parse_definitions!(content, path)
      merge_definitions(acc, defs)
    end)
  end

  defp merge_definitions(left, right) do
    Map.merge(left, right, fn _module, left_defs, right_defs ->
      MapSet.union(left_defs, right_defs)
    end)
  end

  defp format_missing_files(paths) do
    paths
    |> Enum.map(&Path.expand/1)
    |> Enum.sort()
    |> Enum.map_join("\n", fn path -> "  - #{path}" end)
  end

  defp required_arity(params) do
    params
    |> Enum.filter(fn param ->
      param_kind(param) in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]
    end)
    |> Enum.reject(&param_default?/1)
    |> length()
  end

  defp compute_arity_info(params, info) do
    required_positional = required_arity(params)
    optional_positional = params |> Enum.filter(&optional_positional?/1) |> length()
    has_var_positional = Enum.any?(params, &varargs?/1)
    has_var_keyword = Enum.any?(params, &kwargs?/1)

    required_kw_only =
      params
      |> Enum.filter(&keyword_only_required?/1)
      |> Enum.map(& &1["name"])

    optional_kw_only =
      params
      |> Enum.filter(&keyword_only_optional?/1)
      |> Enum.map(& &1["name"])

    signature_available = Map.get(info, "signature_available", true)
    variadic_fallback = params == [] and signature_available == false

    max_arity =
      case {variadic_fallback, has_var_positional, optional_positional} do
        {true, _, _} ->
          variadic_max_arity() + 1

        {_, true, _} ->
          :unbounded

        {_, _, optional_positional} when optional_positional > 0 ->
          required_positional + 2

        _ ->
          required_positional + 1
      end

    %{
      "required_arity" => required_positional,
      "minimum_arity" => required_positional,
      "maximum_arity" => max_arity,
      "has_var_positional" => has_var_positional,
      "has_var_keyword" => has_var_keyword,
      "required_keyword_only" => required_kw_only,
      "optional_keyword_only" => optional_kw_only
    }
  end

  defp optional_positional?(param) do
    param_kind(param) in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"] and param_default?(param)
  end

  defp varargs?(param), do: param_kind(param) == "VAR_POSITIONAL"
  defp kwargs?(param), do: param_kind(param) == "VAR_KEYWORD"

  defp keyword_only_required?(param) do
    param_kind(param) == "KEYWORD_ONLY" and not param_default?(param)
  end

  defp keyword_only_optional?(param) do
    param_kind(param) == "KEYWORD_ONLY" and param_default?(param)
  end

  defp param_kind(%{"kind" => kind}) when is_binary(kind), do: String.upcase(kind)
  defp param_kind(%{kind: kind}) when is_binary(kind), do: String.upcase(kind)
  defp param_kind(%{kind: kind}), do: kind
  defp param_kind(_), do: nil

  defp param_default?(%{"default" => _}), do: true
  defp param_default?(%{default: _}), do: true
  defp param_default?(_), do: false

  defp variadic_max_arity do
    Application.get_env(:snakebridge, :variadic_max_arity, 8)
  end

  defp sanitize_function_name(python_name) when is_binary(python_name) do
    elixir_name =
      python_name
      |> Macro.underscore()
      |> String.replace(~r/[^a-z0-9_?!]/, "_")
      |> ensure_valid_identifier()

    elixir_name =
      case elixir_name in @reserved_words do
        true -> "py_#{elixir_name}"
        _ -> elixir_name
      end

    {elixir_name, python_name}
  end

  defp ensure_valid_identifier(""), do: "_"

  defp ensure_valid_identifier(name) do
    case String.match?(name, ~r/^[a-z_][a-z0-9_?!]*$/) do
      true -> name
      _ -> "_" <> name
    end
  end

  defp python_name_for_elixir_name(elixir_name) when is_binary(elixir_name) do
    case String.split(elixir_name, "py_", parts: 2) do
      ["", rest] when rest in @reserved_words -> rest
      _ -> elixir_name
    end
  end

  defp format_missing(missing) do
    missing
    |> Enum.sort()
    |> Enum.map_join("\n", fn {mod, fun, arity} ->
      module = Module.split(mod) |> Enum.join(".")
      "  - #{module}.#{fun}/#{arity}"
    end)
  end

  defp scanner_module do
    Application.get_env(:snakebridge, :scanner, Scanner)
  end

  defp read_generated_file!(path) do
    case File.read(path) do
      {:ok, content} ->
        content

      {:error, reason} ->
        raise SnakeBridge.CompileError, """
        Strict mode: Cannot read generated file #{path}: #{inspect(reason)}
        """
    end
  end

  defp parse_definitions!(content, path) do
    case Code.string_to_quoted(content, file: path) do
      {:ok, ast} ->
        collect_definitions(ast)

      {:error, {line, error, token}} ->
        raise SnakeBridge.CompileError, """
        Strict mode: Cannot parse generated file #{path}: #{error} #{inspect(token)} on line #{line}
        """
    end
  end

  defp collect_definitions(ast) do
    initial = %{stack: [], defs: %{}}

    {_, acc} =
      Macro.traverse(ast, initial, &collect_pre/2, &collect_post/2)

    acc.defs
  end

  defp collect_pre({:defmodule, _, [{:__aliases__, _, parts}, _]} = node, acc) do
    segments = module_segments(parts, acc.stack)
    module_name = Enum.join(segments, ".")

    acc =
      acc
      |> Map.update!(:stack, &[segments | &1])
      |> Map.update(:defs, %{}, &Map.put_new(&1, module_name, MapSet.new()))

    {node, acc}
  end

  defp collect_pre({:def, _, [head | _]} = node, acc) do
    {node, track_def(acc, head)}
  end

  defp collect_pre(node, acc), do: {node, acc}

  defp track_def(acc, head) do
    case {def_name(head), List.first(acc.stack)} do
      {nil, _} ->
        acc

      {_, nil} ->
        acc

      {name, current_module} ->
        module_name = Enum.join(current_module, ".")

        Map.update(acc, :defs, %{}, fn defs ->
          Map.update(defs, module_name, MapSet.new([name]), &MapSet.put(&1, name))
        end)
    end
  end

  defp collect_post({:defmodule, _, _} = node, acc) do
    {_popped, rest} = List.pop_at(acc.stack, 0)
    {node, %{acc | stack: rest}}
  end

  defp collect_post(node, acc), do: {node, acc}

  defp module_segments(parts, []) do
    Enum.map(parts, &Atom.to_string/1)
  end

  defp module_segments(parts, [parent | _]) do
    parent ++ Enum.map(parts, &Atom.to_string/1)
  end

  defp def_name({:when, _, [inner | _]}), do: def_name(inner)
  defp def_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp def_name(_), do: nil

  defp function_defined?(defs, module, name) when is_binary(module) and is_binary(name) do
    case Map.get(defs, module) do
      nil -> false
      set -> MapSet.member?(set, name)
    end
  end

  defp method_expected_name(%{"elixir_name" => name}) when is_binary(name), do: name
  defp method_expected_name(%{elixir_name: name}) when is_binary(name), do: name

  defp method_expected_name(%{"name" => name}) when is_binary(name) do
    case Generator.sanitize_method_name(name) do
      {elixir_name, _} -> elixir_name
      _ -> ""
    end
  end

  defp method_expected_name(%{name: name}) when is_binary(name) do
    case Generator.sanitize_method_name(name) do
      {elixir_name, _} -> elixir_name
      _ -> ""
    end
  end

  defp method_expected_name(_), do: ""

  defp missing_functions_message([]), do: ""

  defp missing_functions_message(missing) do
    formatted =
      missing
      |> Enum.map_join("\n", fn info ->
        module = info["module"] || "Unknown"
        name = info["name"] || "unknown"
        "  - #{module}.#{name}"
      end)

    """
    Missing functions:
    #{formatted}

    """
  end

  defp missing_classes_message([]), do: ""

  defp missing_classes_message(missing) do
    formatted =
      missing
      |> Enum.map_join("\n", fn info ->
        info["module"] || "Unknown"
      end)

    """
    Missing classes:
    #{formatted}

    """
  end

  defp missing_class_members_message([]), do: ""

  defp missing_class_members_message(missing) do
    formatted =
      missing
      |> Enum.map_join("\n", fn {module, name} ->
        "  - #{module}.#{name}"
      end)

    """
    Missing class members:
    #{formatted}

    """
  end

  defp count_symbols(manifest) do
    symbols = Map.get(manifest, "symbols", %{}) |> map_size()
    classes = Map.get(manifest, "classes", %{}) |> map_size()
    symbols + classes
  end

  defp generate_helper_wrappers(config) do
    case Helpers.enabled?(config) do
      true ->
        case Helpers.discover(config) do
          {:ok, helpers} ->
            HelperGenerator.generate_helpers(helpers, config)

          {:error, %SnakeBridge.HelperRegistryError{} = error} ->
            Mix.shell().error(Exception.message(error))
            :ok

          {:error, reason} ->
            Mix.shell().error("Helper registry failed: #{inspect(reason)}")
            :ok
        end

      _ ->
        :ok
    end
  end
end
