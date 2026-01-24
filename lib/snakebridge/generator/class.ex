defmodule SnakeBridge.Generator.Class do
  @moduledoc false

  alias SnakeBridge.Generator

  @reserved_attribute_names ["new"]

  @spec render_class(map(), SnakeBridge.Config.Library.t()) :: String.t()
  def render_class(class_info, library) do
    class_name = Generator.class_name(class_info)
    python_module = Generator.class_python_module(class_info, library)
    module_name = Generator.class_module_name(class_info, library)
    relative_module = Generator.relative_module_name(library, module_name)
    moduledoc = render_class_moduledoc(class_info["docstring"], class_name)

    methods = class_info["methods"] || []
    attrs = class_info["attributes"] || []

    init_method = Enum.find(methods, fn method -> method["name"] == "__init__" end)
    init_docstring = if init_method, do: init_method["docstring"], else: nil
    init_params = if init_method, do: init_method["parameters"] || [], else: []
    init_params = drop_self_param(init_params)
    plan = Generator.build_params(init_params, init_method || %{})
    param_names = Enum.map(plan.required, & &1.name)
    args_name = Generator.extra_args_name(param_names)

    constructor =
      if plan.is_variadic do
        render_variadic_constructor(plan, args_name, init_docstring, class_name)
      else
        render_constructor(plan, args_name, init_params, init_docstring, class_name)
      end

    methods =
      methods
      |> Enum.reject(fn method -> method["name"] == "__init__" end)
      |> rename_new_method_if_collision(init_method)
      |> deduplicate_methods()

    methods_source = Enum.map_join(methods, "\n\n", &render_method(&1, class_name))
    method_names = resolved_method_names(methods)

    attrs_source =
      attrs
      |> resolve_attribute_names(method_names)
      |> Enum.map_join("\n\n", &render_attribute/1)

    """
      defmodule #{relative_module} do
    #{Generator.indent(moduledoc, 4)}
        def __snakebridge_python_name__, do: "#{python_module}"
        def __snakebridge_python_class__, do: "#{class_name}"
        def __snakebridge_library__, do: "#{library.python_name}"
        @opaque t :: SnakeBridge.Ref.t()

    #{Generator.indent(constructor, 4)}

    #{Generator.indent(methods_source, 4)}

    #{Generator.indent(attrs_source, 4)}
      end
    """
  end

  @doc """
  Renders a class as a standalone top-level module for split layout.

  Unlike `render_class/2` which renders with a relative module name for nesting,
  this function uses the fully-qualified module name for standalone files.
  """
  @spec render_class_standalone(map(), SnakeBridge.Config.Library.t(), module() | String.t()) ::
          String.t()
  def render_class_standalone(class_info, library, elixir_module) do
    class_name = Generator.class_name(class_info)
    python_module = Generator.class_python_module(class_info, library)
    module_name = module_to_string(elixir_module)
    moduledoc = render_class_moduledoc(class_info["docstring"], class_name)

    methods = class_info["methods"] || []
    attrs = class_info["attributes"] || []

    init_method = Enum.find(methods, fn method -> method["name"] == "__init__" end)
    init_docstring = if init_method, do: init_method["docstring"], else: nil
    init_params = if init_method, do: init_method["parameters"] || [], else: []
    init_params = drop_self_param(init_params)
    plan = Generator.build_params(init_params, init_method || %{})
    param_names = Enum.map(plan.required, & &1.name)
    args_name = Generator.extra_args_name(param_names)

    constructor =
      if plan.is_variadic do
        render_variadic_constructor(plan, args_name, init_docstring, class_name)
      else
        render_constructor(plan, args_name, init_params, init_docstring, class_name)
      end

    methods =
      methods
      |> Enum.reject(fn method -> method["name"] == "__init__" end)
      |> rename_new_method_if_collision(init_method)
      |> deduplicate_methods()

    methods_source = Enum.map_join(methods, "\n\n", &render_method(&1, class_name))
    method_names = resolved_method_names(methods)

    attrs_source =
      attrs
      |> resolve_attribute_names(method_names)
      |> Enum.map_join("\n\n", &render_attribute/1)

    """
    defmodule #{module_name} do
    #{Generator.indent(moduledoc, 2)}
      def __snakebridge_python_name__, do: "#{python_module}"
      def __snakebridge_python_class__, do: "#{class_name}"
      def __snakebridge_library__, do: "#{library.python_name}"
      @opaque t :: SnakeBridge.Ref.t()

    #{Generator.indent(constructor, 2)}

    #{Generator.indent(methods_source, 2)}

    #{Generator.indent(attrs_source, 2)}
    end
    """
  end

  defp module_to_string(module) when is_atom(module) do
    module |> Module.split() |> Enum.join(".")
  end

  defp module_to_string(module) when is_binary(module), do: module

  defp render_class_moduledoc(docstring, class_name) do
    formatted =
      docstring
      |> Generator.format_docstring()
      |> String.trim()

    content =
      if formatted == "" do
        "Wrapper for Python class #{class_name}."
      else
        formatted
      end

    Enum.join(["@moduledoc \"\"\"", content, "\"\"\""], "\n")
  end

  defp render_doc_attribute(docstring, params, return_type, indent, fallback) do
    formatted =
      docstring
      |> Generator.format_docstring_with_fallback(params, return_type, fallback)
      |> String.trim()

    if formatted == "" do
      ""
    else
      indent_str = String.duplicate(" ", indent)
      content = Generator.indent(formatted, indent)

      Enum.join(["#{indent_str}@doc \"\"\"", content, "#{indent_str}\"\"\""], "\n")
    end
  end

  defp render_constructor(plan, args_name, init_params, init_docstring, class_name) do
    param_names = Enum.map(plan.required, & &1.name)
    args = Generator.args_expr(param_names, plan.has_args, args_name)

    param_list = Generator.param_list(param_names, plan.has_args, plan.has_opts, args_name)

    call = "SnakeBridge.Runtime.call_class(__MODULE__, :__init__, #{args}, opts)"

    doc_block =
      render_doc_attribute(
        init_docstring,
        init_params,
        nil,
        8,
        fallback_constructor_doc(class_name)
      )

    doc_block = if doc_block == "", do: "", else: doc_block <> "\n"

    spec_args =
      plan.required
      |> Enum.map(&Generator.param_type_spec/1)
      |> Generator.maybe_add_args_spec(plan.has_args)
      |> Kernel.++(["keyword()"])

    spec_args_str = Enum.join(spec_args, ", ")
    normalize = Generator.normalize_args_line(plan.has_args, args_name, 10)
    kw_validation = Generator.keyword_only_validation(plan.required_keyword_only, 10)

    """
    #{doc_block}        @spec new(#{spec_args_str}) :: {:ok, SnakeBridge.Ref.t()} | {:error, Snakepit.Error.t()}
        def new(#{param_list}) do
    #{normalize}#{kw_validation}          #{call}
        end
    """
  end

  defp render_method(%{"name" => "__init__"}, _class_name), do: ""
  defp render_method(%{name: "__init__"}, _class_name), do: ""

  defp render_method(info, class_name) do
    python_name = info["python_name"] || info["name"] || info[:name] || ""
    name_info = resolve_method_name(info, python_name)
    do_render_method(name_info, info, class_name, python_name)
  end

  defp resolve_method_name(info, python_name) do
    case info["elixir_name"] || info[:elixir_name] do
      elixir_name when is_binary(elixir_name) -> {elixir_name, python_name}
      _ -> Generator.sanitize_method_name(python_name)
    end
  end

  defp do_render_method(nil, _info, _class_name, _python_name), do: ""

  defp do_render_method({name, python_name}, info, class_name, _original_python_name) do
    params =
      info["parameters"]
      |> List.wrap()
      |> drop_self_param()

    plan = Generator.build_params(params, info)
    return_type = info["return_type"] || %{"type" => "any"}
    docstring = info["docstring"]
    render_method_body(name, python_name, plan, return_type, docstring, params, class_name)
  end

  defp render_method_body(
         name,
         python_name,
         %{is_variadic: true},
         return_type,
         docstring,
         _params,
         class_name
       ) do
    render_variadic_method(name, python_name, return_type, docstring, class_name)
  end

  defp render_method_body(name, python_name, plan, return_type, docstring, params, class_name) do
    param_names = Enum.map(plan.required, & &1.name)
    args_name = Generator.extra_args_name(param_names)
    spec = Generator.method_spec(name, plan.required, plan.has_args, return_type)
    call = Generator.runtime_method_call(name, python_name, param_names, plan.has_args, args_name)
    normalize = Generator.normalize_args_line(plan.has_args, args_name, 10)
    kw_validation = Generator.keyword_only_validation(plan.required_keyword_only, 10)

    doc_block =
      render_doc_attribute(
        docstring,
        params,
        return_type,
        8,
        fallback_method_doc(class_name, python_name)
      )

    doc_block = if doc_block == "", do: "", else: doc_block <> "\n"

    """
    #{doc_block}        #{spec}
        def #{name}(ref#{Generator.method_param_suffix(param_names, plan.has_args, plan.has_opts, args_name)}) do
    #{normalize}#{kw_validation}          #{call}
        end
    """
  end

  defp render_attribute({elixir_name, python_name}) do
    """
        @spec #{elixir_name}(SnakeBridge.Ref.t()) :: {:ok, term()} | {:error, Snakepit.Error.t()}
        def #{elixir_name}(ref) do
          SnakeBridge.Runtime.get_attr(ref, :#{python_name})
        end
    """
  end

  defp resolve_attribute_names(attrs, method_names) do
    reserved = attribute_reserved_names(method_names)

    {resolved, _used} =
      Enum.map_reduce(attrs, reserved, fn attr, used ->
        {elixir_name, python_name} = sanitize_attribute_name(attr)
        {unique_name, used} = ensure_unique_attr_name(elixir_name, used)
        {{unique_name, python_name}, used}
      end)

    resolved
  end

  defp attribute_reserved_names(method_names) do
    method_names
    |> MapSet.new()
    |> MapSet.union(MapSet.new(@reserved_attribute_names))
  end

  defp ensure_unique_attr_name(name, used) do
    if MapSet.member?(used, name) do
      unique_attr_name(name <> "_attr", used, 2)
    else
      {name, MapSet.put(used, name)}
    end
  end

  defp unique_attr_name(candidate, used, counter) do
    if MapSet.member?(used, candidate) do
      unique_attr_name(candidate <> Integer.to_string(counter), used, counter + 1)
    else
      {candidate, MapSet.put(used, candidate)}
    end
  end

  defp resolved_method_names(methods) do
    methods
    |> Enum.map(fn method ->
      python_name = method["python_name"] || method["name"] || method[:name] || ""

      case resolve_method_name(method, python_name) do
        {elixir_name, _python_name} -> elixir_name
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp sanitize_attribute_name(attr) do
    elixir_name =
      attr
      |> Macro.underscore()
      |> String.replace(~r/[^a-z0-9_]/, "_")
      |> ensure_valid_attr_identifier()

    {elixir_name, attr}
  end

  defp ensure_valid_attr_identifier(""), do: "_attr"

  defp ensure_valid_attr_identifier(name) do
    if String.match?(name, ~r/^[a-z_][a-z0-9_]*$/) do
      name
    else
      "_" <> name
    end
  end

  defp drop_self_param(params) when is_list(params) do
    Enum.reject(params, fn param ->
      name = param["name"] || param[:name]
      name in ["self", "cls"]
    end)
  end

  # Rename the Python 'new' method to 'python_new' when there's an __init__ constructor.
  # This avoids collision with the generated 'new' constructor.
  defp rename_new_method_if_collision(methods, nil), do: methods

  defp rename_new_method_if_collision(methods, _init_method) do
    Enum.map(methods, fn method ->
      if method["name"] == "new" do
        Map.put(method, "elixir_name", "python_new")
      else
        method
      end
    end)
  end

  # Deduplicate methods by their resolved Elixir name, preferring those with more parameters
  # This handles cases where introspection finds multiple signatures for the same method
  # AND cases where different Python methods map to the same Elixir name (e.g., __getitem__ -> get, get -> get)
  defp deduplicate_methods(methods) do
    methods
    |> Enum.group_by(&method_group_key/1)
    |> Enum.reject(fn {name, _} -> is_nil(name) end)
    |> Enum.map(fn {_name, group} ->
      # Keep the one with the most parameters (or most complex signature)
      # Prefer the "real" method name over dunder methods when param counts are equal
      Enum.max_by(group, &method_rank/1)
    end)
  end

  defp method_group_key(method) do
    python_name = method["python_name"] || method["name"] || method[:name] || ""

    case resolve_method_name(method, python_name) do
      {elixir_name, _python_name} -> elixir_name
      nil -> nil
    end
  end

  defp method_rank(method) do
    params = method["parameters"] || method[:parameters] || []
    python_name = method["name"] || method[:name] || ""
    # Give slight preference to non-dunder methods
    {length(params), if(dunder_method?(python_name), do: 0, else: 1)}
  end

  defp dunder_method?(python_name) do
    String.starts_with?(python_name, "__") && String.ends_with?(python_name, "__")
  end

  defp fallback_constructor_doc(class_name) do
    "Constructs `#{class_name}`."
  end

  defp fallback_method_doc(class_name, python_name) do
    "Python method `#{class_name}.#{python_name}`."
  end

  defp render_variadic_constructor(_plan, _args_name, init_docstring, class_name) do
    max_arity = Generator.variadic_max_arity()
    specs = variadic_specs("new", max_arity, "SnakeBridge.Ref.t()")
    clauses = variadic_constructor_clauses(max_arity)

    doc_block =
      render_doc_attribute(init_docstring, [], nil, 8, fallback_constructor_doc(class_name))

    doc_block = if doc_block == "", do: "", else: doc_block <> "\n"

    """
    #{doc_block}        #{specs}
    #{Generator.indent(clauses, 8)}
    """
  end

  defp render_variadic_method(name, python_name, return_type, docstring, class_name) do
    max_arity = Generator.variadic_max_arity()
    return_spec = Generator.type_spec_string(return_type)
    specs = variadic_method_specs(name, max_arity, return_spec)
    clauses = variadic_method_clauses(name, python_name, max_arity)

    doc_block =
      render_doc_attribute(
        docstring,
        [],
        return_type,
        8,
        fallback_method_doc(class_name, python_name)
      )

    doc_block = if doc_block == "", do: "", else: doc_block <> "\n"

    """
    #{doc_block}        #{specs}
    #{Generator.indent(clauses, 8)}
    """
  end

  defp variadic_specs(name, max_arity, return_spec) do
    Enum.map_join(0..max_arity, "\n", fn arity ->
      args = variadic_term_args(arity)
      variadic_spec_pair(name, args, return_spec)
    end)
  end

  defp variadic_term_args(0), do: []
  defp variadic_term_args(arity), do: Enum.map(1..arity, fn _ -> "term()" end)

  defp variadic_spec_pair(name, args, return_spec) do
    spec_no_opts =
      "@spec #{name}(#{Enum.join(args, ", ")}) :: {:ok, #{return_spec}} | {:error, Snakepit.Error.t()}"

    spec_with_opts =
      "@spec #{name}(#{Enum.join(args ++ ["keyword()"], ", ")}) :: {:ok, #{return_spec}} | {:error, Snakepit.Error.t()}"

    spec_no_opts <> "\n" <> spec_with_opts
  end

  defp variadic_method_specs(name, max_arity, return_spec) do
    Enum.map_join(0..max_arity, "\n", fn arity ->
      args = ["SnakeBridge.Ref.t()" | variadic_term_args(arity)]
      variadic_spec_pair(name, args, return_spec)
    end)
  end

  defp variadic_constructor_clauses(max_arity) do
    Enum.map_join(0..max_arity, "\n\n", fn arity ->
      args = variadic_args(arity)
      args_list = variadic_args_list(args)
      build_variadic_constructor_clause(arity, args, args_list)
    end)
  end

  defp build_variadic_constructor_clause(0, args, args_list) do
    no_args_clause =
      variadic_constructor_no_opts_clause(variadic_param_list(args), args_list)

    opts_clause =
      variadic_constructor_opts_clause(
        variadic_param_list_with_opts(args),
        args_list
      )

    no_args_clause <> "\n\n" <> opts_clause
  end

  defp build_variadic_constructor_clause(_arity, args, args_list) do
    positional_clause =
      variadic_constructor_no_opts_clause(variadic_param_list(args), args_list)

    opts_clause =
      variadic_constructor_opts_clause(
        variadic_param_list_with_opts(args),
        args_list
      )

    positional_clause <> "\n\n" <> opts_clause
  end

  defp variadic_method_clauses(name, python_name, max_arity) do
    Enum.map_join(0..max_arity, "\n\n", fn arity ->
      args = variadic_args(arity)
      args_list = variadic_args_list(args)
      build_variadic_method_clause(name, python_name, arity, args, args_list)
    end)
  end

  defp build_variadic_method_clause(name, python_name, 0, args, args_list) do
    no_args_clause =
      variadic_method_no_opts_clause(
        name,
        python_name,
        variadic_method_param_list(args),
        args_list
      )

    opts_clause =
      variadic_method_opts_clause(
        name,
        python_name,
        variadic_method_param_list_with_opts(args),
        args_list
      )

    no_args_clause <> "\n\n" <> opts_clause
  end

  defp build_variadic_method_clause(name, python_name, _arity, args, args_list) do
    positional_clause =
      variadic_method_no_opts_clause(
        name,
        python_name,
        variadic_method_param_list(args),
        args_list
      )

    opts_clause =
      variadic_method_opts_clause(
        name,
        python_name,
        variadic_method_param_list_with_opts(args),
        args_list
      )

    positional_clause <> "\n\n" <> opts_clause
  end

  defp variadic_constructor_no_opts_clause(params, args_list) do
    call = "SnakeBridge.Runtime.call_class(__MODULE__, :__init__, #{args_list}, [])"

    """
    def new(#{params}) do
      #{call}
    end
    """
  end

  defp variadic_constructor_opts_clause(params, args_list) do
    call = "SnakeBridge.Runtime.call_class(__MODULE__, :__init__, #{args_list}, opts)"

    """
    def new(#{params}) when #{Generator.opts_guard()} do
      #{call}
    end
    """
  end

  defp variadic_method_no_opts_clause(name, python_name, params, args_list) do
    call =
      "SnakeBridge.Runtime.call_method(ref, #{Generator.function_ref(name, python_name)}, #{args_list}, [])"

    """
    def #{name}(#{params}) do
      #{call}
    end
    """
  end

  defp variadic_method_opts_clause(name, python_name, params, args_list) do
    call =
      "SnakeBridge.Runtime.call_method(ref, #{Generator.function_ref(name, python_name)}, #{args_list}, opts)"

    """
    def #{name}(#{params}) when #{Generator.opts_guard()} do
      #{call}
    end
    """
  end

  defp variadic_args(arity) when is_integer(arity) and arity > 0 do
    Enum.map(1..arity, &"arg#{&1}")
  end

  defp variadic_args(_arity), do: []

  defp variadic_args_list([]), do: "[]"
  defp variadic_args_list(args), do: "[" <> Enum.join(args, ", ") <> "]"

  defp variadic_param_list([]), do: ""
  defp variadic_param_list(args), do: Enum.join(args, ", ")

  defp variadic_param_list_with_opts([]), do: "opts"
  defp variadic_param_list_with_opts(args), do: Enum.join(args ++ ["opts"], ", ")

  defp variadic_method_param_list(args), do: Enum.join(["ref" | args], ", ")
  defp variadic_method_param_list_with_opts(args), do: Enum.join(["ref" | args] ++ ["opts"], ", ")
end
