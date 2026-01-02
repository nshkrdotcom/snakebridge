defmodule SnakeBridge.Generator.Function do
  @moduledoc false

  alias SnakeBridge.Generator

  @spec render_function(map(), SnakeBridge.Config.Library.t()) :: String.t()
  def render_function(info, library) do
    raw_name = info["name"] || ""
    python_name = info["python_name"] || info["function"] || raw_name
    {name, _python_name} = Generator.sanitize_function_name(raw_name)

    if module_attribute?(info) do
      render_module_attribute(name, python_name, info)
    else
      render_callable_function(info, library, name, python_name)
    end
  end

  defp render_callable_function(info, library, name, python_name) do
    params = info["parameters"] || []
    doc = info["docstring"] || ""
    plan = Generator.build_params(params, info)
    param_names = Enum.map(plan.required, & &1.name)
    args_name = Generator.extra_args_name(param_names)
    return_type = info["return_type"] || %{"type" => "any"}

    normal = render_function_body(name, python_name, plan, args_name, return_type, doc, params)
    maybe_add_streaming(normal, name, python_name, plan, args_name, library)
  end

  defp render_function_body(name, python_name, plan, args_name, return_type, doc, params) do
    if plan.is_variadic do
      render_variadic_function(name, python_name, return_type, doc, params)
    else
      render_normal_function(name, python_name, plan, args_name, return_type, doc, params)
    end
  end

  defp maybe_add_streaming(normal, name, python_name, plan, args_name, library) do
    is_streaming = python_name in (library.streaming || [])

    if is_streaming do
      streaming = render_streaming_body(name, python_name, plan, args_name)
      normal <> "\n\n" <> streaming
    else
      normal
    end
  end

  defp render_streaming_body(name, python_name, plan, args_name) do
    if plan.is_variadic do
      render_variadic_streaming_variant(name, python_name)
    else
      render_streaming_variant(name, python_name, plan, args_name)
    end
  end

  defp module_attribute?(info) do
    info["call_type"] == "module_attr" or info[:call_type] == "module_attr" or
      info["type"] == "attribute" or info[:type] == "attribute"
  end

  defp render_module_attribute(name, python_name, info) do
    return_type = info["return_type"] || %{"type" => "any"}
    doc = info["docstring"] || ""
    formatted_doc = Generator.format_docstring(doc, [], return_type)
    attr_ref = Generator.function_ref(name, python_name)
    return_spec = Generator.type_spec_string(return_type)

    """
      @doc \"\"\"
      #{String.trim(formatted_doc)}
      \"\"\"
      @spec #{name}() :: {:ok, #{return_spec}} | {:error, Snakepit.Error.t()}
      def #{name}() do
        SnakeBridge.Runtime.get_module_attr(__MODULE__, #{attr_ref})
      end
    """
  end

  defp render_normal_function(name, python_name, plan, args_name, return_type, doc, params) do
    param_names = Enum.map(plan.required, & &1.name)
    args = Generator.args_expr(param_names, plan.has_args, args_name)
    call = Generator.runtime_call(name, python_name, args)
    spec = Generator.function_spec(name, plan.required, plan.has_args, return_type)
    formatted_doc = Generator.format_docstring(doc, params, return_type)
    normalize = Generator.normalize_args_line(plan.has_args, args_name, 8)
    kw_validation = Generator.keyword_only_validation(plan.required_keyword_only, 8)

    """
      @doc \"\"\"
      #{String.trim(formatted_doc)}
      \"\"\"
      #{spec}
      def #{name}(#{Generator.param_list(param_names, plan.has_args, plan.has_opts, args_name)}) do
    #{normalize}#{kw_validation}        #{call}
      end
    """
  end

  defp render_streaming_variant(name, python_name, plan, args_name) do
    param_names = Enum.map(plan.required, & &1.name)
    args = Generator.args_expr(param_names, plan.has_args, args_name)

    stream_params =
      param_names
      |> Generator.maybe_add_args(plan.has_args, args_name)
      |> Kernel.++(["opts \\\\ []", "callback"])

    stream_params_str = Enum.join(stream_params, ", ")

    stream_call = Generator.runtime_stream_call(name, python_name, args)

    spec_args =
      plan.required
      |> Enum.map(&Generator.param_type_spec/1)
      |> Generator.maybe_add_args_spec(plan.has_args)
      |> Kernel.++(["keyword()", "(term() -> any())"])

    spec_args_str = Enum.join(spec_args, ", ")

    base_arity = length(param_names) + if(plan.has_args, do: 2, else: 1)
    normalize = Generator.normalize_args_line(plan.has_args, args_name, 8)
    kw_validation = Generator.keyword_only_validation(plan.required_keyword_only, 8)

    """
      @doc \"\"\"
      Streaming variant of `#{name}/#{base_arity}`.

      The callback receives chunks as they arrive.
      \"\"\"
      @spec #{name}_stream(#{spec_args_str}) :: :ok | {:error, Snakepit.Error.t()}
      def #{name}_stream(#{stream_params_str}) when is_function(callback, 1) do
    #{normalize}#{kw_validation}        #{stream_call}
      end
    """
  end

  defp render_variadic_function(name, python_name, return_type, doc, params) do
    max_arity = Generator.variadic_max_arity()
    return_spec = Generator.type_spec_string(return_type)
    formatted_doc = Generator.format_docstring(doc, params, return_type)
    specs = variadic_specs(name, max_arity, return_spec)
    clauses = variadic_function_clauses(name, python_name, max_arity)

    """
      @doc \"\"\"
      #{String.trim(formatted_doc)}
      \"\"\"
      #{specs}
    #{Generator.indent(clauses, 6)}
    """
  end

  defp render_variadic_streaming_variant(name, python_name) do
    max_arity = Generator.variadic_max_arity()
    specs = variadic_streaming_specs(name, max_arity)
    clauses = variadic_streaming_clauses(name, python_name, max_arity)

    """
      @doc \"\"\"
      Streaming variant of `#{name}`.

      The callback receives chunks as they arrive.
      \"\"\"
      #{specs}
    #{Generator.indent(clauses, 6)}
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

  defp variadic_streaming_specs(name, max_arity) do
    Enum.map_join(0..max_arity, "\n", fn arity ->
      args = variadic_term_args(arity)
      variadic_streaming_spec_pair(name, args)
    end)
  end

  defp variadic_streaming_spec_pair(name, args) do
    callback = "(term() -> any())"

    spec_no_opts =
      "@spec #{name}_stream(#{Enum.join(args ++ [callback], ", ")}) :: :ok | {:error, Snakepit.Error.t()}"

    spec_with_opts =
      "@spec #{name}_stream(#{Enum.join(args ++ ["keyword()", callback], ", ")}) :: :ok | {:error, Snakepit.Error.t()}"

    spec_no_opts <> "\n" <> spec_with_opts
  end

  defp variadic_function_clauses(name, python_name, max_arity) do
    Enum.map_join(0..max_arity, "\n\n", fn arity ->
      args = variadic_args(arity)
      args_list = variadic_args_list(args)
      build_variadic_function_clause(name, python_name, arity, args, args_list)
    end)
  end

  defp build_variadic_function_clause(name, python_name, 0, args, args_list) do
    no_args_clause =
      variadic_no_opts_clause(name, python_name, variadic_param_list(args), args_list)

    opts_clause =
      variadic_opts_clause(
        name,
        python_name,
        variadic_param_list_with_opts(args),
        args_list
      )

    no_args_clause <> "\n\n" <> opts_clause
  end

  defp build_variadic_function_clause(name, python_name, _arity, args, args_list) do
    positional_clause =
      variadic_no_opts_clause(name, python_name, variadic_param_list(args), args_list)

    opts_clause =
      variadic_opts_clause(
        name,
        python_name,
        variadic_param_list_with_opts(args),
        args_list
      )

    positional_clause <> "\n\n" <> opts_clause
  end

  defp variadic_streaming_clauses(name, python_name, max_arity) do
    Enum.map_join(0..max_arity, "\n\n", fn arity ->
      args = variadic_args(arity)
      args_list = variadic_args_list(args)
      build_variadic_streaming_clause(name, python_name, arity, args, args_list)
    end)
  end

  defp build_variadic_streaming_clause(name, python_name, 0, args, args_list) do
    no_args_clause =
      variadic_streaming_no_opts_clause(
        name,
        python_name,
        variadic_streaming_param_list(args),
        args_list
      )

    opts_clause =
      variadic_streaming_opts_clause(
        name,
        python_name,
        variadic_streaming_param_list_with_opts(args),
        args_list
      )

    no_args_clause <> "\n\n" <> opts_clause
  end

  defp build_variadic_streaming_clause(name, python_name, _arity, args, args_list) do
    positional_clause =
      variadic_streaming_no_opts_clause(
        name,
        python_name,
        variadic_streaming_param_list(args),
        args_list
      )

    opts_clause =
      variadic_streaming_opts_clause(
        name,
        python_name,
        variadic_streaming_param_list_with_opts(args),
        args_list
      )

    positional_clause <> "\n\n" <> opts_clause
  end

  defp variadic_no_opts_clause(name, python_name, params, args_list) do
    call = Generator.runtime_call(name, python_name, args_list, "[]")

    """
    def #{name}(#{params}) do
      #{call}
    end
    """
  end

  defp variadic_opts_clause(name, python_name, params, args_list) do
    call = Generator.runtime_call(name, python_name, args_list, "opts")

    """
    def #{name}(#{params}) when #{Generator.opts_guard()} do
      #{call}
    end
    """
  end

  defp variadic_streaming_no_opts_clause(name, python_name, params, args_list) do
    call = Generator.runtime_stream_call(name, python_name, args_list, "[]")

    """
    def #{name}_stream(#{params}) when is_function(callback, 1) do
      #{call}
    end
    """
  end

  defp variadic_streaming_opts_clause(name, python_name, params, args_list) do
    call = Generator.runtime_stream_call(name, python_name, args_list, "opts")

    """
    def #{name}_stream(#{params}) when #{Generator.opts_guard()} and is_function(callback, 1) do
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

  defp variadic_streaming_param_list(args), do: Enum.join(args ++ ["callback"], ", ")

  defp variadic_streaming_param_list_with_opts(args),
    do: Enum.join(args ++ ["opts", "callback"], ", ")
end
