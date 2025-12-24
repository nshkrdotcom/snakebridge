defmodule SnakeBridge.Generator do
  @moduledoc """
  Code generation engine for SnakeBridge.

  Generates Elixir modules from Python library descriptors using
  metaprogramming and AST manipulation. Now uses TypeMapper for
  proper typespec emission.
  """

  alias SnakeBridge.Generator.Helpers
  alias SnakeBridge.TypeSystem.Mapper

  @doc """
  Generate module AST from class descriptor.

  Takes a class descriptor and configuration, returns quoted Elixir code
  that defines a module with create/execute functions.
  """
  @spec generate_module(map(), SnakeBridge.Config.t()) :: Macro.t()
  def generate_module(descriptor, config) do
    # Support both struct and map descriptors
    descriptor_name = Helpers.get_field(descriptor, :name, "Unknown")
    elixir_module = Helpers.get_field(descriptor, :elixir_module)
    python_path = Helpers.get_field(descriptor, :python_path, "")
    methods = Helpers.get_field(descriptor, :methods, [])
    constant_fields = Helpers.get_field(descriptor, :constant_fields, [])
    constructor = Helpers.get_field(descriptor, :constructor, %{})

    module_name =
      cond do
        elixir_module ->
          elixir_module

        python_path != "" ->
          Helpers.module_name(python_path)

        true ->
          Module.concat([String.to_atom(descriptor_name)])
      end

    compilation_mode = config.compilation_mode

    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(Helpers.build_moduledoc(descriptor))

        @python_path unquote(python_path)
        @config unquote(Macro.escape(config))

        @type t :: {session_id :: String.t(), instance_id :: String.t()}

        unquote_splicing(generate_constant_attributes(constant_fields))

        unquote(generate_hooks(compilation_mode))

        unquote(generate_create_function(python_path, constructor))

        unquote_splicing(generate_methods(methods))

        defp generate_session_id do
          SnakeBridge.SessionId.generate("session")
        end
      end
    end
  end

  @doc """
  Generate module AST for Python module-level functions.

  Different from class modules - no instance creation, direct function calls.
  Functions are stateless and call Runtime.call_function instead of create_instance.
  """
  @spec generate_function_module(map(), SnakeBridge.Config.t()) :: Macro.t()
  def generate_function_module(descriptor, config) do
    # Support both struct and map descriptors
    descriptor_name = Helpers.get_field(descriptor, :name, "Unknown")
    elixir_module = Helpers.get_field(descriptor, :elixir_module)
    python_path = Helpers.get_field(descriptor, :python_path, "")
    functions = Helpers.get_field(descriptor, :functions, [])

    module_name =
      cond do
        elixir_module ->
          elixir_module

        python_path != "" ->
          Helpers.module_name(python_path)

        true ->
          Module.concat([String.to_atom(descriptor_name)])
      end

    compilation_mode = config.compilation_mode

    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(Helpers.build_moduledoc(descriptor))

        @python_path unquote(python_path)
        @config unquote(Macro.escape(config))

        unquote(generate_hooks(compilation_mode))

        unquote_splicing(generate_functions(functions, python_path))

        defp generate_session_id do
          SnakeBridge.SessionId.generate("session")
        end
      end
    end
  end

  # Generate create function with proper typespec
  defp generate_create_function(python_path, _constructor) do
    # Note: params and return_type from constructor can be used for enhanced typespecs in future

    quote do
      @doc """
      Create a new instance of #{unquote(python_path)}.

      Returns `{:ok, {session_id, instance_id}}` on success.
      """
      @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
      def create(args \\ %{}, opts \\ []) do
        session_id = Keyword.get(opts, :session_id, generate_session_id())

        SnakeBridge.Runtime.create_instance(
          unquote(python_path),
          args,
          session_id,
          opts
        )
      end
    end
  end

  defp generate_constant_attributes(constant_fields) when is_list(constant_fields) do
    Enum.map(constant_fields, fn field_name ->
      attr_name =
        field_name
        |> String.downcase()
        |> String.to_atom()

      {:@, [], [{attr_name, [], [nil]}]}
    end)
  end

  defp generate_hooks(:compile_time) do
    quote do
      @before_compile SnakeBridge.Generator.Hooks
    end
  end

  defp generate_hooks(:runtime) do
    quote do
      @on_load :__snakebridge_load__

      def __snakebridge_load__ do
        :ok
      end
    end
  end

  defp generate_hooks(_auto_or_other) do
    quote do
    end
  end

  defp generate_methods(methods) when is_list(methods) do
    Enum.map(methods, fn method ->
      method_name = Helpers.get_field(method, :name) || raise "Method must have name"

      elixir_name =
        Helpers.get_field(method, :elixir_name) ||
          Helpers.normalize_function_name(method_name, nil)

      _streaming = Helpers.get_field(method, :streaming, false)
      _params = Helpers.get_field(method, :parameters, [])
      return_type = Helpers.get_field(method, :return_type)

      # Generate typespec using TypeMapper
      return_spec = Helpers.build_return_spec(return_type)

      quote do
        @doc unquote(Helpers.build_function_doc(method))
        @spec unquote(elixir_name)(t(), map(), keyword()) ::
                {:ok, unquote(return_spec)} | {:error, term()}
        def unquote(elixir_name)(instance_ref, args \\ %{}, opts \\ []) do
          SnakeBridge.Runtime.call_method(
            instance_ref,
            unquote(method_name),
            args,
            opts
          )
        end
      end
    end)
  end

  defp generate_functions(functions, module_python_path) when is_list(functions) do
    Enum.map(functions, fn function ->
      function_name = Helpers.get_field(function, :name) || raise "Function must have name"

      elixir_name =
        Helpers.get_field(function, :elixir_name) ||
          Helpers.normalize_function_name(function_name, nil)

      docstring = Helpers.get_field(function, :docstring, "")
      _params = Helpers.get_field(function, :parameters, [])
      return_type = Helpers.get_field(function, :return_type)
      streaming = Helpers.get_field(function, :streaming, false)
      streaming_tool = Helpers.get_field(function, :streaming_tool)

      function_python_path =
        Helpers.get_field(function, :python_path) ||
          "#{module_python_path}.#{function_name}"

      # Generate typespec using TypeMapper
      return_spec = Helpers.build_return_spec(return_type)

      stream_function =
        generate_stream_function_if_needed(
          streaming,
          elixir_name,
          function_name,
          function_python_path,
          streaming_tool
        )

      quote do
        @doc """
        Call #{unquote(function_name)} Python function.

        #{unquote(docstring)}
        """
        @spec unquote(elixir_name)(map(), keyword()) ::
                {:ok, unquote(return_spec)} | {:error, term()}
        def unquote(elixir_name)(args \\ %{}, opts \\ []) do
          session_id = Keyword.get(opts, :session_id, generate_session_id())

          SnakeBridge.Runtime.call_function(
            unquote(function_python_path),
            unquote(function_name),
            args,
            Keyword.put(opts, :session_id, session_id)
          )
        end

        unquote(stream_function)
      end
    end)
  end

  @doc """
  Optimize generated AST.

  Applies various optimization passes to improve generated code.
  """
  @spec optimize(Macro.t()) :: Macro.t()
  def optimize(ast) do
    ast
    |> remove_unused_imports()
    |> inline_constants()
  end

  defp remove_unused_imports(ast) do
    Macro.prewalk(ast, fn
      {:import, _, _} -> nil
      node -> node
    end)
    |> remove_nils()
  end

  defp inline_constants(ast) do
    Macro.prewalk(ast, fn
      node -> node
    end)
  end

  defp remove_nils(ast) do
    Macro.prewalk(ast, fn
      {:__block__, meta, items} when is_list(items) ->
        {:__block__, meta, Enum.reject(items, &is_nil/1)}

      {:defmodule, meta, [alias, [do: {:__block__, block_meta, items}]]} ->
        {:defmodule, meta, [alias, [do: {:__block__, block_meta, Enum.reject(items, &is_nil/1)}]]}

      node ->
        node
    end)
  end

  @doc """
  Generate all modules for an integration.
  """
  @spec generate_all(SnakeBridge.Config.t()) :: {:ok, [module()]} | {:error, term()}
  def generate_all(%SnakeBridge.Config{} = config) do
    case SnakeBridge.Config.validate(config) do
      {:ok, valid_config} ->
        class_results = compile_class_modules(valid_config.classes, valid_config)
        function_results = generate_function_modules(valid_config.functions, valid_config)
        all_results = class_results ++ function_results

        collect_results(all_results)

      {:error, _errors} = error ->
        error
    end
  end

  @doc """
  Generate all module ASTs for an integration (no compilation).
  """
  @spec generate_all_ast(SnakeBridge.Config.t()) :: [Macro.t()]
  def generate_all_ast(%SnakeBridge.Config{} = config) do
    class_asts =
      Enum.map(config.classes, fn class_descriptor ->
        generate_module(class_descriptor, config)
      end)

    function_asts = generate_function_module_asts(config.functions, config)

    class_asts ++ function_asts
  end

  defp generate_function_modules(functions, config) when is_list(functions) do
    grouped_functions = group_functions_by_module(functions)

    Enum.map(grouped_functions, fn {module_info, funcs} ->
      descriptor = %{
        name: module_info.name,
        python_path: module_info.python_path,
        elixir_module: module_info.elixir_module,
        docstring: config.description || "",
        functions: funcs
      }

      ast = generate_function_module(descriptor, config)

      case compile_and_load(ast) do
        {:ok, module} -> {:ok, module}
        {:error, _} = error -> error
      end
    end)
  end

  defp generate_function_module_asts(functions, config) when is_list(functions) do
    grouped_functions = group_functions_by_module(functions)

    Enum.map(grouped_functions, fn {module_info, funcs} ->
      descriptor = %{
        name: module_info.name,
        python_path: module_info.python_path,
        elixir_module: module_info.elixir_module,
        docstring: config.description || "",
        functions: funcs
      }

      generate_function_module(descriptor, config)
    end)
  end

  defp group_functions_by_module(functions) do
    functions
    |> Enum.group_by(fn func ->
      python_path = Helpers.get_field(func, :python_path, "")

      case String.split(python_path, ".") do
        [single] -> single
        parts -> Enum.take(parts, length(parts) - 1) |> Enum.join(".")
      end
    end)
    |> Enum.map(fn {module_path, funcs} ->
      elixir_module =
        Helpers.get_field(List.first(funcs), :elixir_module) ||
          module_path_to_elixir_module(module_path)

      module_info = %{
        name: "#{elixir_module}Functions",
        python_path: module_path,
        elixir_module: elixir_module
      }

      {module_info, funcs}
    end)
  end

  defp module_path_to_elixir_module(python_path) when is_binary(python_path) do
    Mapper.python_class_to_elixir_module(python_path)
  end

  # Compile class modules from descriptors
  defp compile_class_modules(class_descriptors, config) do
    Enum.map(class_descriptors, fn class_descriptor ->
      ast = generate_module(class_descriptor, config)

      case compile_and_load(ast) do
        {:ok, module} -> {:ok, module}
        {:error, _} = error -> error
      end
    end)
  end

  # Collect results from module generation, returning first error or all successful modules
  defp collect_results(all_results) do
    case Enum.find(all_results, &match?({:error, _}, &1)) do
      {:error, _reason} = error ->
        error

      nil ->
        modules = Enum.map(all_results, fn {:ok, module} -> module end)
        {:ok, modules}
    end
  end

  # Generate stream function if streaming is enabled
  defp generate_stream_function_if_needed(
         false,
         _elixir_name,
         _function_name,
         _function_python_path,
         _streaming_tool
       ) do
    nil
  end

  defp generate_stream_function_if_needed(
         true,
         elixir_name,
         function_name,
         function_python_path,
         streaming_tool
       ) do
    stream_name = :"#{elixir_name}_stream"

    quote do
      @doc """
      Stream #{unquote(function_name)} Python function.
      """
      @spec unquote(stream_name)(map(), keyword()) :: Enumerable.t()
      def unquote(stream_name)(args \\ %{}, opts \\ []) do
        unquote(
          generate_stream_function_body(function_python_path, function_name, streaming_tool)
        )
      end
    end
  end

  # Generate the body of a stream function based on the streaming tool
  defp generate_stream_function_body(function_python_path, function_name, streaming_tool) do
    quote do
      case unquote(streaming_tool) do
        nil ->
          SnakeBridge.Runtime.stream_function(
            unquote(function_python_path),
            unquote(function_name),
            args,
            opts
          )

        tool_name when tool_name in ["call_python_stream", :call_python_stream] ->
          SnakeBridge.Runtime.stream_function(
            unquote(function_python_path),
            unquote(function_name),
            args,
            opts
          )

        tool_name ->
          session_id = Keyword.get(opts, :session_id, generate_session_id())
          SnakeBridge.Runtime.stream_tool(session_id, tool_name, args, opts)
      end
    end
  end

  @doc """
  Generate only changed modules from diff.
  """
  @spec generate_incremental(list(), [module()]) :: {:ok, [module()]} | {:error, term()}
  def generate_incremental(diff, existing_modules) do
    changed_modules =
      diff
      |> Enum.filter(&match?({:modified, _, _, _}, &1))
      |> Enum.map(fn {:modified, _path, _old, _new} ->
        if length(existing_modules) > 0, do: hd(existing_modules), else: nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, changed_modules}
  end

  @doc """
  Compile and load generated module at runtime.

  Used in development mode for hot reloading.
  """
  @spec compile_and_load(Macro.t()) :: {:ok, module()} | {:error, term()}
  def compile_and_load(ast) do
    [{module, _bytecode}] = Code.compile_quoted(ast)
    {:ok, module}
  rescue
    e -> {:error, Exception.message(e)}
  end
end
