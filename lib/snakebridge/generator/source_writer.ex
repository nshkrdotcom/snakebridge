defmodule SnakeBridge.Generator.SourceWriter do
  @moduledoc """
  Generates formatted Elixir source code from Python introspection data.

  This module takes introspection data (as produced by `Introspector`) and
  generates complete, formatted Elixir module source code with proper
  documentation, typespecs, and function definitions.

  ## Features

  - Generates modular file structure (not monolithic)
  - Splits functions by namespace/submodule
  - Places classes in `classes/` subdirectory
  - Generates `_meta.ex` with discovery helpers
  - Adds `@moduledoc` from Python docstrings
  - Generates `@spec` declarations from Python type annotations
  - Creates `@doc` strings for each function
  - Formats output using `Code.format_string!/2`

  ## Output Structure

  ```
  lib/snakebridge/adapters/<library>/
  ├── <library>.ex          # Main module with top-level functions
  ├── <submodule>.ex        # One file per Python submodule/namespace
  ├── classes/
  │   └── <class>.ex        # One file per class
  └── _meta.ex              # Discovery helpers
  ```

  ## Example

      iex> introspection = %{
      ...>   "module" => "mylib",
      ...>   "functions" => [
      ...>     %{
      ...>       "name" => "add",
      ...>       "parameters" => [
      ...>         %{"name" => "a", "type" => %{"type" => "int"}},
      ...>         %{"name" => "b", "type" => %{"type" => "int"}}
      ...>       ],
      ...>       "return_type" => %{"type" => "int"},
      ...>       "docstring" => %{"summary" => "Add two numbers"}
      ...>     }
      ...>   ]
      ...> }
      iex> files = SourceWriter.generate(introspection, module_name: "MyLib")
      iex> files["mylib.ex"] =~ "defmodule MyLib do"
      true

  """

  alias SnakeBridge.Generator.{TypeMapper, DocFormatter, MetaGenerator}

  @default_opts [
    module_name: nil,
    use_snakebridge: true,
    add_python_annotations: true,
    base_path: "lib/snakebridge/adapters"
  ]

  @doc """
  Generates formatted Elixir source code from introspection data.

  Returns a map of file paths to source code content. This allows generating
  multiple files in a modular structure instead of one monolithic file.

  ## Parameters

    * `introspection` - The introspection map from `Introspector.introspect/1`
    * `opts` - Keyword list of options:
      - `:module_name` - The Elixir module name (defaults to CamelCase of Python module)
      - `:use_snakebridge` - Whether to add `use SnakeBridge.Adapter` (default: true)
      - `:add_python_annotations` - Whether to add `@python_function` annotations (default: true)
      - `:base_path` - Base directory path for generated files (default: "lib/snakebridge/adapters")

  ## Returns

  A map of `%{relative_path => source_code}` where:
  - Keys are relative file paths (e.g., "numpy/numpy.ex", "numpy/classes/ndarray.ex")
  - Values are formatted Elixir source code strings

  ## Examples

      iex> introspection = %{"module" => "math", "functions" => [...]}
      iex> files = SourceWriter.generate(introspection)
      iex> files["math/math.ex"] =~ "defmodule Math do"
      true
      iex> Map.has_key?(files, "math/_meta.ex")
      true

  """
  @spec generate(map(), keyword()) :: %{String.t() => String.t()}
  def generate(introspection, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    base_module_name = get_module_name(introspection, opts)
    python_module = Map.get(introspection, "module", "python_module")
    library_name = python_module |> String.split(".") |> List.first() |> Macro.underscore()

    # Group functions by namespace/submodule
    functions = Map.get(introspection, "functions", [])
    functions_by_module = group_functions_by_namespace(functions, base_module_name, python_module)

    # Get classes
    classes = Map.get(introspection, "classes", [])

    # Generate main module file
    main_module_functions = Map.get(functions_by_module, base_module_name, [])

    main_source =
      build_main_module(
        introspection,
        base_module_name,
        main_module_functions,
        classes,
        functions_by_module,
        opts
      )

    files = %{"#{library_name}/#{library_name}.ex" => main_source}

    # Generate submodule files
    files =
      functions_by_module
      |> Enum.reject(fn {module, _} -> module == base_module_name end)
      |> Enum.reduce(files, fn {module, funcs}, acc ->
        submodule_name = module |> module_to_string() |> String.split(".") |> List.last()
        file_name = "#{library_name}/#{Macro.underscore(submodule_name)}.ex"
        source = build_submodule(module, funcs, opts)
        Map.put(acc, file_name, source)
      end)

    # Generate class files
    files =
      Enum.reduce(classes, files, fn class_info, acc ->
        class_name = class_info["name"]
        file_name = "#{library_name}/classes/#{Macro.underscore(class_name)}.ex"
        source = build_class_module(class_info, base_module_name, opts)
        Map.put(acc, file_name, source)
      end)

    # Generate _meta.ex file
    meta_source = MetaGenerator.generate(base_module_name, functions_by_module, classes)
    files = Map.put(files, "#{library_name}/_meta.ex", meta_source)

    files
  end

  @doc """
  Generates and writes multiple files from introspection data.

  ## Parameters

    * `introspection` - The introspection map
    * `base_output_path` - Base directory where files should be written
    * `opts` - Options (same as `generate/2`)

  ## Returns

    * `{:ok, files, stats}` - Files written successfully with statistics
    * `{:error, reason}` - Failed to write files

  Where:
    * `files` - List of relative file paths that were written
    * `stats` - Map with generation statistics

  """
  @spec generate_files(map(), String.t(), keyword()) ::
          {:ok, list(String.t()), map()} | {:error, term()}
  def generate_files(introspection, base_output_path, opts \\ []) do
    files_map = generate(introspection, opts)

    written_files =
      Enum.reduce_while(files_map, [], fn {relative_path, source}, acc ->
        full_path = Path.join(base_output_path, relative_path)
        dir = Path.dirname(full_path)

        with :ok <- File.mkdir_p(dir),
             :ok <- File.write(full_path, source) do
          # Show progress
          Mix.shell().info("  Writing #{full_path}")
          {:cont, [relative_path | acc]}
        else
          {:error, reason} ->
            {:halt, {:error, {relative_path, reason}}}
        end
      end)

    case written_files do
      {:error, reason} ->
        {:error, reason}

      paths ->
        stats = calculate_stats(introspection, files_map)
        {:ok, Enum.reverse(paths), stats}
    end
  end

  @doc """
  Legacy function for backward compatibility.

  Generates a single monolithic file (the old behavior).

  ## Parameters

    * `introspection` - The introspection map
    * `output_path` - Path where the source file should be written
    * `opts` - Options (same as `generate/2`)

  ## Returns

    * `:ok` - File written successfully
    * `{:error, reason}` - Failed to write file

  """
  @spec generate_file(map(), String.t(), keyword()) :: :ok | {:error, term()}
  def generate_file(introspection, output_path, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    module_name = get_module_name(introspection, opts)
    module_ast = build_module_ast_legacy(introspection, module_name, opts)

    source =
      module_ast
      |> Macro.to_string()
      |> Code.format_string!()
      |> IO.iodata_to_binary()

    File.write(output_path, source)
  end

  # Private Functions

  defp calculate_stats(introspection, files_map) do
    functions = Map.get(introspection, "functions", [])
    classes = Map.get(introspection, "classes", [])
    base_module = get_base_module_name(introspection)

    # Extract submodule names from generated files
    submodules =
      files_map
      |> Map.keys()
      |> Enum.filter(fn path ->
        # Filter out main file, meta file, and class files
        !String.ends_with?(path, "/_meta.ex") &&
          !String.contains?(path, "/classes/")
      end)
      |> Enum.map(fn path ->
        # Extract module name from path like "numpy/linalg.ex"
        path
        |> Path.basename(".ex")
        |> Macro.camelize()
      end)
      |> Enum.reject(fn name -> name == base_module end)

    %{
      functions: length(functions),
      classes: length(classes),
      submodules: submodules
    }
  end

  defp get_base_module_name(introspection) do
    python_module = Map.get(introspection, "module", "python_module")

    python_module
    |> String.split(".")
    |> List.first()
    |> Macro.camelize()
  end

  @spec get_module_name(map(), keyword()) :: Macro.t()
  defp get_module_name(introspection, opts) do
    case Keyword.get(opts, :module_name) do
      nil ->
        # Use Python module name
        case introspection do
          %{"module" => python_module} ->
            python_module
            |> String.split(".")
            |> Enum.map(&Macro.camelize/1)
            |> Enum.join(".")
            |> parse_module_name()

          _ ->
            parse_module_name("PythonModule")
        end

      name ->
        parse_module_name(name)
    end
  end

  @spec parse_module_name(String.t() | atom()) :: Macro.t()
  defp parse_module_name(name) when is_atom(name) do
    name |> Atom.to_string() |> parse_module_name()
  end

  defp parse_module_name(name) when is_binary(name) do
    parts =
      name
      |> String.split(".")
      |> Enum.map(&String.to_atom/1)

    {:__aliases__, [alias: false], parts}
  end

  # New helper functions for multi-file generation

  @spec group_functions_by_namespace(list(map()), Macro.t(), String.t()) :: map()
  defp group_functions_by_namespace(functions, base_module_name, _python_module_base) do
    base_module_str = module_to_string(base_module_name)

    Enum.group_by(functions, fn func ->
      func_name = func["name"]

      # Check if function name contains a namespace separator (e.g., "linalg.norm")
      case String.split(func_name, ".", parts: 2) do
        [_single_name] ->
          # No namespace, belongs to base module
          base_module_name

        [namespace, _rest] ->
          # Has namespace, create submodule
          submodule_name = Macro.camelize(namespace)
          parse_module_name("#{base_module_str}.#{submodule_name}")
      end
    end)
  end

  @spec build_main_module(
          map(),
          Macro.t(),
          list(map()),
          list(map()),
          map(),
          keyword()
        ) :: String.t()
  defp build_main_module(
         introspection,
         module_name,
         functions,
         _classes,
         functions_by_module,
         opts
       ) do
    moduledoc = DocFormatter.module_doc(introspection)
    function_asts = Enum.map(functions, &build_function_ast(&1, opts))

    # Build discovery delegates
    module_name_str = module_to_string(module_name)
    meta_module = parse_module_name("#{module_name_str}.Meta")

    delegate_asts =
      quote do
        defdelegate __functions__, to: unquote(meta_module), as: :functions
        defdelegate __classes__, to: unquote(meta_module), as: :classes
        defdelegate __submodules__, to: unquote(meta_module), as: :submodules
        defdelegate __search__(query), to: unquote(meta_module), as: :search
      end

    # Build alias statements for submodules
    alias_asts =
      functions_by_module
      |> Map.keys()
      |> Enum.reject(&(&1 == module_name))
      |> Enum.map(fn submodule ->
        quote do
          alias unquote(submodule)
        end
      end)

    module_ast =
      quote do
        defmodule unquote(module_name) do
          @moduledoc unquote(moduledoc)

          unquote_splicing(build_adapter_use(opts))
          unquote_splicing([delegate_asts])
          unquote_splicing(alias_asts)
          unquote_splicing(function_asts)
        end
      end

    module_ast
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  @spec build_submodule(Macro.t(), list(map()), keyword()) :: String.t()
  defp build_submodule(module_name, functions, opts) do
    function_asts = Enum.map(functions, &build_function_ast(&1, opts))

    module_ast =
      quote do
        defmodule unquote(module_name) do
          @moduledoc """
          Python submodule: #{unquote(module_to_string(module_name))}
          """

          unquote_splicing(build_adapter_use(opts))
          unquote_splicing(function_asts)
        end
      end

    module_ast
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  @spec build_class_module(map(), Macro.t(), keyword()) :: String.t()
  defp build_class_module(class_info, base_module_name, opts) do
    base_module_str = module_to_string(base_module_name)
    class_name = class_info["name"] |> to_elixir_module_name()
    full_module_name = parse_module_name("#{base_module_str}.#{class_name}")

    methods = Map.get(class_info, "methods", [])
    doc_string = DocFormatter.function_doc(class_info)

    method_asts =
      methods
      |> Enum.reject(fn m -> m["name"] |> String.starts_with?("__") end)
      |> Enum.map(&build_function_ast(&1, opts))

    module_ast =
      quote do
        defmodule unquote(full_module_name) do
          @moduledoc unquote(doc_string)

          @type t() :: reference()

          unquote_splicing(method_asts)
        end
      end

    module_ast
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  @spec module_to_string(Macro.t() | atom()) :: String.t()
  defp module_to_string(module) when is_atom(module) do
    module |> Module.split() |> Enum.join(".")
  end

  defp module_to_string({:__aliases__, _, parts}) do
    parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
  end

  # Legacy function for backward compatibility
  @spec build_module_ast_legacy(map(), Macro.t(), keyword()) :: Macro.t()
  defp build_module_ast_legacy(introspection, module_name, opts) do
    moduledoc = DocFormatter.module_doc(introspection)

    functions = Map.get(introspection, "functions", [])
    classes = Map.get(introspection, "classes", [])

    function_asts = Enum.map(functions, &build_function_ast(&1, opts))
    class_asts = Enum.map(classes, &build_class_ast(&1, opts))

    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(moduledoc)

        unquote_splicing(build_adapter_use(opts))
        unquote_splicing(function_asts)
        unquote_splicing(class_asts)
      end
    end
  end

  @spec build_adapter_use(keyword()) :: [Macro.t()]
  defp build_adapter_use(opts) do
    if Keyword.get(opts, :use_snakebridge, false) do
      [
        quote do
          use SnakeBridge.Adapter
        end
      ]
    else
      []
    end
  end

  @spec build_function_ast(map(), keyword()) :: Macro.t()
  defp build_function_ast(func_info, opts) do
    python_name = func_info["name"]
    func_name = python_name |> to_elixir_function_name() |> String.to_atom()
    params = Map.get(func_info, "parameters", [])
    return_type = Map.get(func_info, "return_type", %{"type" => "any"})

    doc_string = DocFormatter.function_doc(func_info)
    spec_ast = build_spec_ast(func_name, params, return_type)

    # Build function parameters
    param_vars = build_param_vars(params)

    # Build function body (placeholder - actual implementation would delegate to Python)
    body_ast = build_function_body(func_info, params, opts)

    quote do
      @doc unquote(doc_string)
      unquote(spec_ast)
      unquote_splicing(build_python_annotation(func_info, opts))

      def unquote(func_name)(unquote_splicing(param_vars)) do
        unquote(body_ast)
      end
    end
  end

  @spec build_spec_ast(atom(), list(map()), map()) :: Macro.t()
  defp build_spec_ast(func_name, params, return_type) do
    param_specs =
      params
      |> Enum.map(fn param ->
        TypeMapper.to_spec(param["type"])
      end)

    return_spec = TypeMapper.to_spec(return_type)

    quote do
      @spec unquote(func_name)(unquote_splicing(param_specs)) :: unquote(return_spec)
    end
  end

  @spec build_param_vars(list(map())) :: [Macro.t()]
  defp build_param_vars(params) do
    params
    |> Enum.with_index()
    |> Enum.map(fn {param, idx} ->
      param_name = param["name"] |> sanitize_param_name(idx) |> String.to_atom()
      # Note: We don't generate default values to avoid Elixir's "defaults multiple times" error
      # when the same function is inherited by multiple classes in the same module
      Macro.var(param_name, nil)
    end)
  end

  @spec sanitize_param_name(String.t(), non_neg_integer()) :: String.t()
  defp sanitize_param_name("_", idx), do: "arg#{idx}"
  defp sanitize_param_name("_" <> rest, _idx), do: rest
  defp sanitize_param_name(name, _idx), do: name

  @spec build_python_annotation(map(), keyword()) :: [Macro.t()]
  defp build_python_annotation(func_info, opts) do
    if Keyword.get(opts, :add_python_annotations, true) do
      python_name = func_info["name"]

      [
        quote do
          @python_function unquote(python_name)
        end
      ]
    else
      []
    end
  end

  @spec build_function_body(map(), list(map()), keyword()) :: Macro.t()
  defp build_function_body(func_info, params, _opts) do
    func_name = func_info["name"]

    # Use sanitized parameter names (same as build_param_vars)
    param_names =
      params
      |> Enum.with_index()
      |> Enum.map(fn {p, idx} -> p["name"] |> sanitize_param_name(idx) |> String.to_atom() end)

    # Generate a call to __python_call__ (which would be provided by the Adapter)
    args_list =
      param_names
      |> Enum.map(&Macro.var(&1, nil))

    quote do
      __python_call__(
        unquote(func_name),
        unquote(args_list)
      )
    end
  end

  @spec build_class_ast(map(), keyword()) :: Macro.t()
  defp build_class_ast(class_info, opts) do
    class_name = class_info["name"] |> to_elixir_module_name() |> parse_module_name()
    methods = Map.get(class_info, "methods", [])

    doc_string = DocFormatter.function_doc(class_info)

    method_asts =
      methods
      |> Enum.reject(fn m -> m["name"] |> String.starts_with?("__") end)
      |> Enum.map(&build_function_ast(&1, opts))

    quote do
      defmodule unquote(class_name) do
        @moduledoc unquote(doc_string)

        @type t() :: reference()

        unquote_splicing(method_asts)
      end
    end
  end

  @spec to_elixir_function_name(String.t()) :: String.t()
  defp to_elixir_function_name(name) do
    # Elixir function names must start with lowercase or underscore
    # Convert CamelCase/PascalCase to snake_case
    name
    |> Macro.underscore()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> ensure_valid_identifier()
  end

  @spec to_elixir_module_name(String.t()) :: String.t()
  defp to_elixir_module_name(name) do
    # Elixir module names must start with uppercase
    # Convert snake_case to CamelCase if needed
    name
    |> Macro.camelize()
  end

  defp ensure_valid_identifier(name) do
    # Ensure name starts with lowercase letter or underscore
    case name do
      <<first::utf8, _rest::binary>> when first >= ?a and first <= ?z ->
        name

      <<first::utf8, _rest::binary>> when first == ?_ ->
        name

      <<first::utf8, _rest::binary>> when first >= ?0 and first <= ?9 ->
        # Starts with digit, prefix with underscore
        "_" <> name

      "" ->
        "_unnamed"

      _ ->
        # Starts with something else, prefix with underscore
        "_" <> name
    end
  end
end
