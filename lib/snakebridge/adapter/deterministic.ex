defmodule SnakeBridge.Adapter.Deterministic do
  @moduledoc """
  Deterministic adapter creation using introspection.

  This module creates adapters without using an AI agent by:
  1. Introspecting the Python library to get functions/signatures
  2. Filtering to stateless functions
  3. Generating manifest JSON
  4. Generating Python bridge if needed
  5. Validating the manifest

  Falls back to agent-based creation only if this approach fails.
  """

  require Logger

  alias SnakeBridge.Discovery.Introspector
  alias SnakeBridge.Manifest

  @stateful_keywords [
    # File I/O
    "open",
    "read",
    "write",
    "close",
    "file",
    "path",
    "mkdir",
    "rmdir",
    "remove",
    "unlink",
    # Network
    "socket",
    "connect",
    "request",
    "fetch",
    "download",
    "upload",
    "http",
    "url",
    "api",
    # Database
    "cursor",
    "execute",
    "commit",
    "rollback",
    "transaction",
    "query",
    "database",
    # Threading/async
    "thread",
    "lock",
    "mutex",
    "async",
    "await",
    "concurrent",
    "pool",
    # GUI
    "window",
    "widget",
    "button",
    "canvas",
    "display",
    "render",
    "draw",
    "gui",
    # Pickle/eval
    "pickle",
    "unpickle",
    "eval",
    "exec",
    "compile"
  ]

  @type create_result :: %{
          manifest_path: String.t(),
          bridge_path: String.t() | nil,
          functions: [map()],
          needs_bridge: boolean()
        }

  @doc """
  Create an adapter deterministically.

  Returns {:ok, result} if successful, {:error, reason} if introspection fails.
  """
  @spec create(String.t(), String.t(), keyword()) ::
          {:ok, create_result()} | {:error, term()}
  def create(_lib_path, lib_name, opts \\ []) do
    max_functions = Keyword.get(opts, :max_functions, 100)
    on_output = Keyword.get(opts, :on_output, &default_output/1)

    on_output.("🔍 Introspecting #{lib_name}...\n")

    with {:ok, schema} <- introspect_library(lib_name, on_output),
         {:ok, functions} <- extract_functions(schema, max_functions, on_output),
         {:ok, manifest} <- build_manifest(lib_name, functions, on_output),
         {:ok, manifest_path} <- write_manifest(lib_name, manifest, on_output),
         {:ok, bridge_path} <- maybe_write_bridge(lib_name, functions, on_output),
         {:ok, example_path} <- write_example(lib_name, manifest, on_output),
         :ok <- validate_manifest(manifest_path, on_output) do
      {:ok,
       %{
         manifest_path: manifest_path,
         bridge_path: bridge_path,
         example_path: example_path,
         functions: functions,
         needs_bridge: bridge_path != nil
       }}
    end
  end

  defp introspect_library(lib_name, on_output) do
    on_output.("  → Running Python introspection...\n")

    case Introspector.discover(Introspector, lib_name, depth: 2) do
      {:ok, schema} ->
        function_count = count_functions(schema)
        on_output.("  ✓ Found #{function_count} functions/methods\n")
        {:ok, schema}

      {:error, reason} ->
        on_output.("  ✗ Introspection failed: #{inspect(reason)}\n")
        {:error, {:introspection_failed, reason}}
    end
  end

  defp count_functions(schema) do
    functions = Map.get(schema, "functions", %{})
    classes = Map.get(schema, "classes", %{})

    function_count = if is_map(functions), do: map_size(functions), else: length(functions)

    method_count =
      classes
      |> normalize_to_list()
      |> Enum.reduce(0, fn item, acc ->
        class_data = extract_class_data(item)
        methods = Map.get(class_data, "methods", [])
        acc + length(methods)
      end)

    function_count + method_count
  end

  # Normalize classes which can be a map or a list of tuples/maps
  defp normalize_to_list(data) when is_map(data) do
    Enum.map(data, fn {name, value} -> {name, value} end)
  end

  defp normalize_to_list(data) when is_list(data), do: data
  defp normalize_to_list(_), do: []

  defp extract_class_data({_name, data}) when is_map(data), do: data
  defp extract_class_data(data) when is_map(data), do: data
  defp extract_class_data(_), do: %{}

  defp extract_functions(schema, max_functions, on_output) do
    on_output.("  → Extracting functions...\n")

    # Get module-level functions (not class methods - those need instances)
    # Functions can be a map %{name => data} or a list
    functions_raw = Map.get(schema, "functions", %{})

    functions =
      if is_map(functions_raw) do
        Enum.map(functions_raw, fn {_name, data} -> data end)
      else
        functions_raw
      end

    # Filter out private functions, annotate with stateless metadata
    public_functions =
      functions
      |> Enum.reject(&is_private?/1)
      |> Enum.map(fn func ->
        Map.put(func, "stateless", is_likely_stateless?(func))
      end)
      |> Enum.take(max_functions)

    stateless_count = Enum.count(public_functions, & &1["stateless"])

    if Enum.empty?(public_functions) do
      on_output.("  ✗ No public functions found\n")
      {:error, :no_public_functions}
    else
      on_output.(
        "  ✓ Found #{length(public_functions)} functions (#{stateless_count} stateless)\n"
      )

      {:ok, public_functions}
    end
  end

  defp is_private?(function) do
    name = Map.get(function, "name", "")
    String.starts_with?(name, "_")
  end

  defp is_likely_stateless?(function) do
    name = Map.get(function, "name", "")
    docstring = Map.get(function, "docstring", "")
    params = Map.get(function, "parameters", [])

    if name in ["main", "__main__"] do
      false
    else
      doc_lower = String.downcase(docstring || "")
      combined = String.downcase("#{name} #{docstring}")

      not Enum.any?(@stateful_keywords, fn keyword ->
        String.contains?(combined, keyword)
      end) and not has_self_param?(params) and
        not has_non_primitive_required_param?(params, doc_lower)
    end
  end

  defp has_self_param?(params) when is_list(params) do
    case params do
      [%{"name" => "self"} | _] -> true
      [%{name: "self"} | _] -> true
      _ -> false
    end
  end

  defp has_self_param?(_), do: false

  defp has_non_primitive_required_param?(params, doc_lower) when is_list(params) do
    Enum.any?(params, fn param ->
      required = Map.get(param, "required", true)
      kind = param_kind(param)
      type_hint = param_type(param)

      required and kind not in ["var_positional", "var_keyword"] and
        non_primitive_type_hint?(type_hint) and
        (doc_mentions_complex_object?(doc_lower) or type_indicates_complex_object?(type_hint))
    end)
  end

  defp has_non_primitive_required_param?(_, _), do: false

  defp build_manifest(lib_name, functions, on_output) do
    on_output.("  → Building manifest...\n")

    # Check if any function has bytes input/output (needs bridge)
    needs_bridge = Enum.any?(functions, &needs_type_conversion?/1)

    python_path_prefix =
      if needs_bridge do
        "bridges.#{bridge_module_name(lib_name)}"
      else
        lib_name
      end

    # Handle dotted module names like urllib.parse -> UrllibParse
    safe_module_name =
      lib_name
      |> String.replace(".", "_")
      |> Macro.camelize()

    manifest = %{
      "name" => lib_name,
      "python_module" => lib_name,
      "python_path_prefix" => python_path_prefix,
      "version" => nil,
      "category" => "utilities",
      "elixir_module" => "SnakeBridge.#{safe_module_name}",
      "pypi_package" => lib_name |> String.split(".") |> List.first(),
      "description" => "SnakeBridge adapter for #{lib_name}",
      "status" => "experimental",
      "types" => extract_types(functions),
      "functions" => Enum.map(functions, &format_function/1)
    }

    on_output.("  ✓ Manifest built (#{length(functions)} functions)\n")
    {:ok, manifest}
  end

  defp needs_type_conversion?(function) do
    params = Map.get(function, "parameters", [])
    return_type = Map.get(function, "return_type", "")
    doc_lower = function |> Map.get("docstring", "") |> String.downcase()

    # Check for bytes, bytearray, or complex types
    types_to_check = [return_type | Enum.map(params, &Map.get(&1, "type", ""))]

    type_needs_conversion =
      Enum.any?(types_to_check, fn type ->
        type_str = to_string(type)
        String.contains?(type_str, "bytes") or String.contains?(type_str, "bytearray")
      end)

    doc_mentions_bytes =
      String.contains?(doc_lower, ["bytes", "bytearray", "byte string", "bytes-like", "binary"])

    params_need_bytes =
      Enum.any?(params, fn p ->
        name = String.downcase(Map.get(p, "name", ""))
        bytes_param?(name, doc_lower, Map.get(p, "type"))
      end)

    type_needs_conversion or doc_mentions_bytes or params_need_bytes
  end

  defp extract_types(functions) do
    functions
    |> Enum.flat_map(fn func ->
      params = Map.get(func, "parameters", [])
      Enum.map(params, fn p -> {Map.get(p, "name"), infer_type(Map.get(p, "type"))} end)
    end)
    |> Enum.uniq_by(fn {name, _} -> name end)
    |> Map.new()
  end

  defp infer_type(nil), do: "any"
  defp infer_type("str"), do: "string"
  defp infer_type("int"), do: "integer"
  defp infer_type("float"), do: "float"
  defp infer_type("bool"), do: "boolean"
  defp infer_type("list"), do: "list"
  defp infer_type("dict"), do: "map"
  defp infer_type("bytes"), do: "string"
  defp infer_type("bytearray"), do: "string"
  defp infer_type(other) when is_binary(other), do: "any"
  defp infer_type(_), do: "any"

  defp format_function(function) do
    name = Map.get(function, "name", "unknown")
    params = Map.get(function, "parameters", [])
    return_type = Map.get(function, "return_type")
    docstring = Map.get(function, "docstring", "")
    stateless = Map.get(function, "stateless", true)

    # Keep full param info (skip self if present)
    formatted_params =
      params
      |> Enum.reject(fn p -> Map.get(p, "name") == "self" end)
      |> Enum.map(fn p ->
        %{
          "name" => Map.get(p, "name"),
          "required" => Map.get(p, "required", true),
          "default" => Map.get(p, "default"),
          "kind" => Map.get(p, "kind", "positional_or_keyword")
        }
      end)

    # Also keep simple args list for backward compat
    args = Enum.map(formatted_params, fn p -> p["name"] end)

    %{
      "name" => name,
      "args" => args,
      "params" => formatted_params,
      "returns" => infer_type(return_type),
      "doc" => String.slice(docstring || "", 0, 200),
      "stateless" => stateless
    }
  end

  defp write_manifest(lib_name, manifest, on_output) do
    dir = "priv/snakebridge/manifests"
    path = "#{dir}/#{lib_name}.json"

    on_output.("  → Writing manifest to #{path}...\n")

    with :ok <- File.mkdir_p(dir),
         json <- Jason.encode!(manifest, pretty: true),
         :ok <- File.write(path, json) do
      on_output.("  ✓ Manifest written\n")
      {:ok, path}
    else
      {:error, reason} ->
        on_output.("  ✗ Failed to write manifest: #{inspect(reason)}\n")
        {:error, {:write_failed, reason}}
    end
  end

  defp maybe_write_bridge(lib_name, functions, on_output) do
    if Enum.any?(functions, &needs_type_conversion?/1) do
      write_bridge(lib_name, functions, on_output)
    else
      on_output.("  → No bridge needed (all types JSON-serializable)\n")
      {:ok, nil}
    end
  end

  defp write_bridge(lib_name, functions, on_output) do
    dir = "priv/python/bridges"
    path = "#{dir}/#{bridge_module_name(lib_name)}.py"

    on_output.("  → Writing Python bridge to #{path}...\n")

    bridge_code = generate_bridge_code(lib_name, functions)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, bridge_code) do
      on_output.("  ✓ Bridge written\n")
      {:ok, path}
    else
      {:error, reason} ->
        on_output.("  ✗ Failed to write bridge: #{inspect(reason)}\n")
        {:error, {:write_failed, reason}}
    end
  end

  defp generate_bridge_code(lib_name, functions) do
    function_defs =
      functions
      |> Enum.map(&generate_bridge_function(&1, lib_name))
      |> Enum.join("\n\n")

    """
    \"\"\"SnakeBridge bridge for #{lib_name}.

    Auto-generated bridge for type conversion (bytes <-> base64).
    \"\"\"
    import base64
    import #{lib_name}

    _MISSING = object()

    def _to_bytes(data):
        \"\"\"Convert input to bytes (handles base64 string or raw bytes).\"\"\"
        if data is None:
            return None
        if isinstance(data, bytes):
            return data
        if isinstance(data, str):
            try:
                return base64.b64decode(data)
            except Exception:
                return data.encode('utf-8')
        return bytes(data)

    def _to_bytes_raw(data):
        \"\"\"Convert input to bytes without base64 decoding.\"\"\"
        if data is None:
            return None
        if isinstance(data, bytes):
            return data
        if isinstance(data, str):
            return data.encode('utf-8')
        return bytes(data)

    def _serialize(obj):
        \"\"\"Convert result to JSON-serializable format.\"\"\"
        if obj is None:
            return None
        if isinstance(obj, (str, int, float, bool)):
            return obj
        if isinstance(obj, bytes):
            return base64.b64encode(obj).decode('ascii')
        if isinstance(obj, (list, tuple)):
            return [_serialize(x) for x in obj]
        if isinstance(obj, dict):
            return {str(k): _serialize(v) for k, v in obj.items()}
        if hasattr(obj, '__dict__'):
            return {k: _serialize(v) for k, v in obj.__dict__.items() if not k.startswith('_')}
        return str(obj)

    #{function_defs}
    """
  end

  defp bridge_module_name(lib_name) do
    lib_name
    |> String.replace(".", "_")
    |> Kernel.<>("_bridge")
  end

  defp generate_bridge_function(function, lib_name) do
    name = Map.get(function, "name", "unknown")
    params = Map.get(function, "parameters", [])
    doc_lower = function |> Map.get("docstring", "") |> String.downcase()
    func_lower = String.downcase(name)
    base_encoding = base_encoding_hint(doc_lower, func_lower)

    bytes_converter =
      if base_encoding && String.contains?(func_lower, "decode") do
        "_to_bytes_raw"
      else
        "_to_bytes"
      end

    params = Enum.reject(params, fn p -> Map.get(p, "name") == "self" end)

    signature = build_bridge_signature(params)

    # Check which params need bytes conversion
    conversion_lines =
      params
      |> Enum.reject(fn p -> param_kind(p) in ["var_positional", "var_keyword"] end)
      |> Enum.filter(fn p -> param_bytes_conversion?(p, doc_lower, func_lower) end)
      |> Enum.flat_map(fn p ->
        param_name = Map.get(p, "name")

        if Map.get(p, "required", true) do
          ["    #{param_name} = #{bytes_converter}(#{param_name})"]
        else
          [
            "    if #{param_name} is not _MISSING:",
            "        #{param_name} = #{bytes_converter}(#{param_name})"
          ]
        end
      end)

    call_lines = build_bridge_call_lines(params, lib_name, name)

    lines =
      [
        "def #{name}(#{signature}):",
        "    \"\"\"Wrapper for #{lib_name}.#{name} with type conversion.\"\"\""
      ] ++
        conversion_lines ++ call_lines

    Enum.join(lines, "\n")
  end

  defp build_bridge_signature(params) do
    last_positional_only =
      params
      |> Enum.with_index()
      |> Enum.filter(fn {p, _idx} -> param_kind(p) == "positional_only" end)
      |> List.last()

    last_positional_only_index =
      if last_positional_only, do: elem(last_positional_only, 1), else: nil

    first_keyword_only =
      params
      |> Enum.with_index()
      |> Enum.find(fn {p, _idx} -> param_kind(p) == "keyword_only" end)

    first_keyword_only_index = if first_keyword_only, do: elem(first_keyword_only, 1), else: nil

    has_var_positional =
      Enum.any?(params, fn p -> param_kind(p) == "var_positional" end)

    insert_slash_at =
      if is_nil(last_positional_only_index), do: nil, else: last_positional_only_index + 1

    insert_star_at =
      if is_nil(first_keyword_only_index) or has_var_positional,
        do: nil,
        else: first_keyword_only_index

    parts =
      params
      |> Enum.with_index()
      |> Enum.flat_map(fn {param, idx} ->
        base = []
        base = if insert_slash_at == idx, do: base ++ ["/"], else: base
        base = if insert_star_at == idx, do: base ++ ["*"], else: base
        base ++ [param_signature(param)]
      end)

    parts =
      if insert_slash_at == length(params) do
        parts ++ ["/"]
      else
        parts
      end

    Enum.join(parts, ", ")
  end

  defp param_signature(param) do
    name = param_name(param)
    required = Map.get(param, "required", true)

    case param_kind(param) do
      "var_positional" ->
        "*#{name}"

      "var_keyword" ->
        "**#{name}"

      _ ->
        if required, do: name, else: "#{name}=_MISSING"
    end
  end

  defp build_bridge_call_lines(params, lib_name, name) do
    positional_required =
      params
      |> Enum.filter(fn p ->
        param_kind(p) in ["positional_only", "positional_or_keyword"] and
          Map.get(p, "required", true)
      end)
      |> Enum.map(&param_name/1)

    positional_optional =
      params
      |> Enum.filter(fn p ->
        param_kind(p) == "positional_only" and not Map.get(p, "required", true)
      end)
      |> Enum.map(&param_name/1)

    keyword_required =
      params
      |> Enum.filter(fn p -> param_kind(p) == "keyword_only" and Map.get(p, "required", true) end)
      |> Enum.map(&param_name/1)

    keyword_optional =
      params
      |> Enum.filter(fn p ->
        param_kind(p) in ["keyword_only", "positional_or_keyword"] and
          not Map.get(p, "required", true)
      end)
      |> Enum.map(&param_name/1)

    var_positional =
      params
      |> Enum.find(fn p -> param_kind(p) == "var_positional" end)
      |> case do
        nil -> nil
        p -> param_name(p)
      end

    var_keyword =
      params
      |> Enum.find(fn p -> param_kind(p) == "var_keyword" end)
      |> case do
        nil -> nil
        p -> param_name(p)
      end

    args_line = "    args_list = [#{Enum.join(positional_required, ", ")}]"

    optional_positional_lines =
      Enum.flat_map(positional_optional, fn param ->
        [
          "    if #{param} is not _MISSING:",
          "        args_list.append(#{param})"
        ]
      end)

    kwargs_line = "    call_kwargs = {}"

    required_kw_lines =
      Enum.map(keyword_required, fn param ->
        "    call_kwargs[\"#{param}\"] = #{param}"
      end)

    optional_kw_lines =
      Enum.flat_map(keyword_optional, fn param ->
        [
          "    if #{param} is not _MISSING:",
          "        call_kwargs[\"#{param}\"] = #{param}"
        ]
      end)

    call_parts = ["*args_list"]
    call_parts = if var_positional, do: call_parts ++ ["*#{var_positional}"], else: call_parts
    call_parts = call_parts ++ ["**call_kwargs"]
    call_parts = if var_keyword, do: call_parts ++ ["**#{var_keyword}"], else: call_parts

    call_line = "    result = #{lib_name}.#{name}(#{Enum.join(call_parts, ", ")})"
    return_line = "    return _serialize(result)"

    [args_line] ++
      optional_positional_lines ++
      [kwargs_line] ++
      required_kw_lines ++
      optional_kw_lines ++ [call_line, return_line]
  end

  defp param_kind(param) do
    Map.get(param, "kind") || Map.get(param, :kind) || "positional_or_keyword"
  end

  defp param_name(param) do
    Map.get(param, "name") || Map.get(param, :name)
  end

  defp param_type(param) do
    Map.get(param, "type") || Map.get(param, :type)
  end

  @primitive_type_tokens [
    "str",
    "int",
    "float",
    "bool",
    "list",
    "dict",
    "bytes",
    "bytearray",
    "tuple",
    "set"
  ]
  @known_type_tokens @primitive_type_tokens ++
                       [
                         "any",
                         "none",
                         "optional",
                         "union",
                         "sequence",
                         "iterable",
                         "mapping",
                         "callable",
                         "io",
                         "binaryio",
                         "textio",
                         "pattern",
                         "match",
                         "literal",
                         "typing"
                       ]

  defp non_primitive_type_hint?(type_hint) do
    type_str = type_hint_string(type_hint)
    type_str != "" and not primitive_type_hint?(type_str)
  end

  defp primitive_type_hint?(type_str) do
    has_primitive =
      Enum.any?(@primitive_type_tokens, fn token ->
        Regex.match?(~r/\b#{token}\b/, type_str)
      end)

    has_primitive and not type_has_custom_reference?(type_str)
  end

  defp type_has_custom_reference?(type_str) do
    Regex.scan(~r/[A-Za-z_][A-Za-z0-9_]*/, type_str)
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 in @known_type_tokens))
    |> Enum.any?()
  end

  defp doc_mentions_complex_object?(doc_lower) do
    String.contains?(doc_lower, [
      "object",
      "callable",
      "file-like",
      "file like",
      "filelike",
      "class",
      "instance"
    ])
  end

  defp type_indicates_complex_object?(type_hint) do
    type_str = type_hint_string(type_hint)

    type_str != "" and
      (type_has_custom_reference?(type_str) or
         String.contains?(type_str, ["callable", "io", "file", "class", "type", "instance"]))
  end

  defp type_hint_string(nil), do: ""
  defp type_hint_string(type_hint), do: type_hint |> to_string() |> String.downcase()

  defp write_example(lib_name, manifest, on_output) do
    dir = "examples/generated/#{lib_name}"
    on_output.("  → Generating example scripts in #{dir}/...\n")

    functions = Map.get(manifest, "functions", [])
    {stateless, stateful} = Enum.split_with(functions, & &1["stateless"])

    # Handle dotted module names like urllib.parse -> SnakeBridge.UrllibParse
    safe_module_name =
      lib_name
      |> String.replace(".", "_")
      |> Macro.camelize()

    elixir_module = "SnakeBridge.#{safe_module_name}"

    with :ok <- File.mkdir_p(dir),
         :ok <-
           write_example_file(dir, "stateless_examples.exs", elixir_module, stateless, on_output),
         :ok <-
           write_example_file(dir, "stateful_examples.exs", elixir_module, stateful, on_output),
         :ok <-
           write_all_functions_file(dir, "all_functions.exs", elixir_module, functions, on_output),
         :ok <- write_readme(dir, lib_name, elixir_module, functions, on_output) do
      on_output.("  ✓ Examples generated (#{length(functions)} functions)\n")
      {:ok, dir}
    else
      {:error, reason} ->
        on_output.("  ✗ Failed to write examples: #{inspect(reason)}\n")
        {:error, {:write_failed, reason}}
    end
  end

  defp write_example_file(_dir, _filename, _module, [], _on_output), do: :ok

  defp write_example_file(dir, filename, module, functions, _on_output) do
    path = Path.join(dir, filename)

    examples =
      functions
      |> Enum.map(&generate_function_example(&1, module))
      |> Enum.join("\n\n")

    content = """
    # #{filename}
    # Auto-generated examples for #{module}
    # Run with: mix run #{path}

    Application.ensure_all_started(:snakebridge)
    # Give snakepit time to start
    Process.sleep(1000)

    IO.puts("=" |> String.duplicate(60))
    IO.puts("  #{module} Examples")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("")

    #{examples}

    IO.puts("")
    IO.puts("Done!")
    """

    File.write(path, content)
  end

  defp write_all_functions_file(dir, filename, module, functions, _on_output) do
    path = Path.join(dir, filename)

    function_list =
      functions
      |> Enum.map(fn f ->
        name = f["name"]
        args = f["args"] || []
        stateless = if f["stateless"], do: "stateless", else: "stateful"
        "  {\"#{name}\", #{length(args)}, :#{stateless}}"
      end)
      |> Enum.join(",\n")

    content = """
    # #{filename}
    # Complete function reference for #{module}
    # Run with: mix run #{path}

    Application.ensure_all_started(:snakebridge)
    Process.sleep(1000)

    # All available functions: {name, arity, stateless?}
    functions = [
    #{function_list}
    ]

    IO.puts("=" |> String.duplicate(60))
    IO.puts("  #{module} - All Functions")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("")
    IO.puts("Total functions: \#{length(functions)}")
    IO.puts("Stateless: \#{Enum.count(functions, fn {_, _, s} -> s == :stateless end)}")
    IO.puts("Stateful: \#{Enum.count(functions, fn {_, _, s} -> s == :stateful end)}")
    IO.puts("")

    Enum.each(functions, fn {name, arity, stateless} ->
      marker = if stateless == :stateless, do: "○", else: "●"
      IO.puts("  \#{marker} \#{name}/\#{arity}")
    end)

    IO.puts("")
    IO.puts("Legend: ○ = stateless (pure), ● = stateful (may have side effects)")
    """

    File.write(path, content)
  end

  defp write_readme(dir, lib_name, module, functions, _on_output) do
    path = Path.join(dir, "README.md")
    {stateless, stateful} = Enum.split_with(functions, & &1["stateless"])

    stateless_list =
      stateless
      |> Enum.take(20)
      |> Enum.map(fn f -> "- `#{f["name"]}`" end)
      |> Enum.join("\n")

    stateful_list =
      stateful
      |> Enum.take(20)
      |> Enum.map(fn f -> "- `#{f["name"]}`" end)
      |> Enum.join("\n")

    content = """
    # #{module} Examples

    Auto-generated examples for the `#{lib_name}` Python library.

    ## Quick Start

    ```elixir
    # In IEx
    iex> #{module}.function_name(args)
    ```

    ## Files

    - `all_functions.exs` - Lists all #{length(functions)} available functions
    - `stateless_examples.exs` - Examples of #{length(stateless)} pure functions
    - `stateful_examples.exs` - Examples of #{length(stateful)} stateful functions

    ## Running Examples

    ```bash
    mix run #{dir}/all_functions.exs
    mix run #{dir}/stateless_examples.exs
    ```

    ## Stateless Functions (#{length(stateless)})

    Pure functions with no side effects:

    #{stateless_list}
    #{if length(stateless) > 20, do: "\n... and #{length(stateless) - 20} more", else: ""}

    ## Stateful Functions (#{length(stateful)})

    Functions that may have side effects:

    #{stateful_list}
    #{if length(stateful) > 20, do: "\n... and #{length(stateful) - 20} more", else: ""}
    """

    File.write(path, content)
  end

  defp generate_function_example(function, module) do
    name = function["name"]
    params = function["params"] || []
    doc = function["doc"] || ""
    stateless = function["stateless"]
    elixir_name = example_function_name(name)

    marker = if stateless, do: "○ stateless", else: "● stateful"

    # Only include REQUIRED params - skip optional ones that have defaults
    # Also filter out kwargs-type args
    required_params =
      Enum.filter(params, fn p ->
        is_required = p["required"] == true
        not_kwargs = String.downcase(p["name"] || "") not in ["kwargs", "kw", "args"]
        not_var = param_kind(p) not in ["var_positional", "var_keyword"]
        is_required and not_kwargs and not_var
      end)

    args_map =
      required_params
      |> Enum.map(fn p ->
        arg_name = p["name"]
        value = generate_placeholder_for_param(p, name, doc)
        "#{arg_name}: #{value}"
      end)
      |> Enum.join(", ")

    call =
      if required_params == [] do
        "#{module}.#{elixir_name}()"
      else
        "#{module}.#{elixir_name}(%{#{args_map}})"
      end

    # Truncate doc for display
    short_doc =
      doc
      |> String.split("\n")
      |> List.first()
      |> String.slice(0, 70)

    """
    # #{name} [#{marker}]
    # #{short_doc}
    IO.puts("Testing #{name}...")
    try do
      result = #{call}
      IO.puts("  ✓ #{name}: \#{inspect(result, limit: 3, printable_limit: 50)}")
    rescue
      e -> IO.puts("  ✗ #{name}: \#{Exception.message(e)}")
    end
    """
  end

  defp example_function_name(name) when is_binary(name) do
    name
    |> SnakeBridge.Generator.Helpers.normalize_function_name(nil)
    |> Atom.to_string()
    |> format_elixir_function_name()
  end

  defp example_function_name(_), do: "unknown"

  defp format_elixir_function_name(name) do
    if valid_unquoted_function_name?(name) do
      name
    else
      inspect(name)
    end
  end

  defp valid_unquoted_function_name?(name) do
    String.match?(name, ~r/^[a-z_][a-zA-Z0-9_]*[!?]?$/)
  end

  # Generate placeholder from introspected param info - uses default value to infer type
  defp generate_placeholder_for_param(param, function_name, doc) do
    default = param["default"]
    name = String.downcase(param["name"] || "")
    doc_lower = String.downcase(doc || "")
    func_lower = String.downcase(function_name || "")
    type_hint = param_type(param)

    cond do
      # If we have a default value, infer type from it
      default != nil ->
        infer_placeholder_from_default(default, name, doc_lower, func_lower, type_hint)

      # No default - infer from name patterns and docstring
      true ->
        infer_placeholder_from_context(name, doc_lower, func_lower, type_hint)
    end
  end

  # Infer placeholder from Python default value
  defp infer_placeholder_from_default(default, name, doc_lower, func_lower, type_hint) do
    default_str = to_string(default)

    cond do
      # Boolean
      default_str in ["True", "False"] ->
        String.downcase(default_str)

      # None
      default_str == "None" ->
        "nil"

      # Integer
      Regex.match?(~r/^-?\d+$/, default_str) ->
        default_str

      # Float
      Regex.match?(~r/^-?\d+\.\d+$/, default_str) ->
        default_str

      # Empty list
      default_str == "[]" ->
        "[1, 2, 3]"

      # Empty dict
      default_str == "{}" ->
        "%{}"

      # Empty tuple
      default_str == "()" ->
        "[]"

      # String with quotes
      String.starts_with?(default_str, ["'", "\""]) ->
        # Convert Python string to Elixir string
        inner = default_str |> String.slice(1..-2//1)
        "\"#{inner}\""

      # Bytes literal like b'...'
      String.starts_with?(default_str, "b'") or String.starts_with?(default_str, "b\"") ->
        bytes_placeholder()

      # Otherwise fall back to context
      true ->
        infer_placeholder_from_context(name, doc_lower, func_lower, type_hint)
    end
  end

  # Infer placeholder from parameter name and docstring
  defp infer_placeholder_from_context(name, doc_lower, func_lower, type_hint) do
    base_encoding = base_encoding_hint(doc_lower, func_lower)
    type_hint_placeholder = placeholder_from_type_hint(type_hint, name, base_encoding, func_lower)

    cond do
      json_param?(name, doc_lower, func_lower) ->
        if map_type_hint?(type_hint) do
          "%{}"
        else
          "\"{\\\"hello\\\": \\\"world\\\"}\""
        end

      base_encoding && (bytes_param_name?(name) or bytes_type_hint?(type_hint)) ->
        base_encoded_placeholder(base_encoding, func_lower)

      version_param?(name) ->
        version_placeholder(doc_lower)

      url_param?(name) ->
        "\"https://example.com\""

      encoding_param?(name) ->
        "\"utf-8\""

      method_param?(name, doc_lower) ->
        "\"GET\""

      hash_algorithm_param?(name, doc_lower) ->
        "\"md5\""

      name == "dtype" ->
        "\"int64\""

      name == "kind" ->
        "\"i\""

      name == "char" ->
        "\"f\""

      pattern_param?(name) ->
        "\".*\""

      path_param?(name) ->
        "\"/tmp/test\""

      type_hint_placeholder != nil ->
        type_hint_placeholder

      list_param?(name, doc_lower, func_lower) ->
        list_placeholder(name)

      map_param?(name) ->
        "%{}"

      name in ["b", "bs"] and String.contains?(func_lower, "encoding") ->
        bytes_placeholder()

      bytes_param?(name, doc_lower, type_hint) ->
        bytes_placeholder()

      boolean_param?(name) ->
        "false"

      numeric_param?(name) ->
        "10"

      string_param?(name) ->
        "\"test\""

      true ->
        "\"test\""
    end
  end

  defp json_param?(name, doc_lower, func_lower) do
    json_names = ["s", "json", "data", "body", "text", "string"]

    (String.contains?(doc_lower, "json") and name in json_names) or
      (String.contains?(func_lower, "json") and name in json_names)
  end

  defp base_encoding_hint(doc_lower, func_lower) do
    cond do
      String.contains?(func_lower, "a85") or
          String.contains?(doc_lower, ["ascii85", "ascii-85"]) ->
        :ascii85

      String.contains?(func_lower, "b85") or
          String.contains?(doc_lower, ["base85", "base-85", "base 85"]) ->
        :base85

      String.contains?(func_lower, "b64") or
          String.contains?(doc_lower, ["base64", "base-64", "base 64"]) ->
        :base64

      String.contains?(func_lower, "b32hex") or
          String.contains?(doc_lower, ["base32hex", "base32-hex", "base32 hex"]) ->
        :base32hex

      String.contains?(func_lower, "b32") or
          String.contains?(doc_lower, ["base32", "base-32", "base 32"]) ->
        :base32

      String.contains?(func_lower, "b16") or
          String.contains?(doc_lower, ["base16", "base-16", "base 16"]) ->
        :base16

      true ->
        nil
    end
  end

  defp base_encoded_placeholder(encoding, func_lower) do
    if String.contains?(func_lower, "decode") do
      case encoding do
        :base64 -> "\"SGVsbG8=\""
        :base32hex -> "\"91IMOR3F\""
        :base32 -> "\"JBSWY3DP\""
        :base16 -> "\"48656C6C6F\""
        :base85 -> "\"NM&qnZv\""
        :ascii85 -> "\"87cURDZ\""
      end
    else
      bytes_placeholder()
    end
  end

  defp bytes_placeholder do
    "<<72, 101, 108, 108, 111>>"
  end

  defp placeholder_from_type_hint(type_hint, name, base_encoding, func_lower) do
    type_str = type_hint_string(type_hint)

    cond do
      type_str == "" ->
        nil

      bytes_type_hint?(type_str) ->
        if base_encoding && bytes_param_name?(name) do
          base_encoded_placeholder(base_encoding, func_lower)
        else
          bytes_placeholder()
        end

      String.contains?(type_str, "bool") ->
        "false"

      String.contains?(type_str, "int") ->
        "10"

      String.contains?(type_str, "float") ->
        "1.5"

      String.contains?(type_str, ["dict", "mapping"]) ->
        "%{}"

      String.contains?(type_str, ["list", "tuple", "sequence", "iterable"]) ->
        list_placeholder(name)

      String.contains?(type_str, "str") ->
        "\"test\""

      true ->
        nil
    end
  end

  defp map_type_hint?(type_hint) do
    type_str = type_hint_string(type_hint)
    type_str != "" and String.contains?(type_str, ["dict", "mapping"])
  end

  defp bytes_type_hint?(type_hint) do
    type_str = type_hint_string(type_hint)
    type_str != "" and String.contains?(type_str, ["bytes", "bytearray"])
  end

  defp bytes_param_name?(name) do
    name in ["b", "bs", "s", "data", "byte_str", "bytes"] or
      String.contains?(name, [
        "byte",
        "bytes",
        "buffer",
        "buf",
        "payload",
        "content",
        "binary",
        "blob"
      ])
  end

  defp url_param?(name) do
    String.contains?(name, ["url", "uri", "href"])
  end

  defp version_param?(name) do
    String.contains?(name, "version")
  end

  defp version_placeholder(doc_lower) do
    case version_from_constraints(doc_lower) do
      nil -> "\"3.0.4\""
      version -> "\"#{version}\""
    end
  end

  defp version_from_constraints(doc_lower) do
    doc = doc_lower || ""

    constraints =
      Regex.scan(~r/(>=|<=|>|<)\s*v?(\d+(?:\.\d+){0,2})/, doc)
      |> Enum.map(fn [_, op, version] -> {op, version} end)

    if constraints == [] do
      nil
    else
      {lower, upper} =
        Enum.reduce(constraints, {nil, nil}, fn {op, ver_str}, {low, up} ->
          ver = parse_version_tuple(ver_str)

          case op do
            ">=" -> {max_version(low, ver), up}
            ">" -> {max_version(low, bump_patch(ver)), up}
            "<=" -> {low, min_version(up, ver)}
            "<" -> {low, min_version(up, decrement_version(ver))}
          end
        end)

      candidate =
        cond do
          lower && upper && compare_version(lower, upper) == :gt -> upper
          lower -> lower
          upper -> upper
          true -> nil
        end

      if candidate, do: version_tuple_to_string(candidate), else: nil
    end
  end

  defp parse_version_tuple(version) do
    parts =
      version
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    case parts do
      [major] -> {major, 0, 0}
      [major, minor] -> {major, minor, 0}
      [major, minor, patch | _] -> {major, minor, patch}
      _ -> {0, 0, 0}
    end
  end

  defp version_tuple_to_string({major, minor, patch}) do
    "#{major}.#{minor}.#{patch}"
  end

  defp compare_version({a1, b1, c1}, {a2, b2, c2}) do
    cond do
      a1 < a2 -> :lt
      a1 > a2 -> :gt
      b1 < b2 -> :lt
      b1 > b2 -> :gt
      c1 < c2 -> :lt
      c1 > c2 -> :gt
      true -> :eq
    end
  end

  defp max_version(nil, ver), do: ver
  defp max_version(a, b), do: if(compare_version(a, b) == :lt, do: b, else: a)

  defp min_version(nil, ver), do: ver
  defp min_version(a, b), do: if(compare_version(a, b) == :gt, do: b, else: a)

  defp bump_patch({major, minor, patch}) do
    {major, minor, patch + 1}
  end

  defp decrement_version({major, minor, patch}) do
    cond do
      patch > 0 -> {major, minor, patch - 1}
      minor > 0 -> {major, minor - 1, 9}
      major > 0 -> {major - 1, 9, 9}
      true -> {0, 0, 0}
    end
  end

  defp encoding_param?(name) do
    String.contains?(name, ["encoding", "charset"])
  end

  defp method_param?(name, doc_lower) do
    name == "method" or (String.contains?(doc_lower, "http") and name == "request_method")
  end

  defp hash_algorithm_param?(name, doc_lower) do
    name == "name" and String.contains?(doc_lower, ["hash", "algorithm"])
  end

  defp pattern_param?(name) do
    String.contains?(name, ["pattern", "regex"])
  end

  defp path_param?(name) do
    String.contains?(name, ["path", "file"])
  end

  defp list_param?(name, doc_lower, func_lower) do
    cond do
      name in ["dimensions", "shape"] ->
        true

      name in [
        "data",
        "values",
        "items",
        "seq",
        "sequence",
        "iterable",
        "list",
        "array",
        "arr",
        "matrix",
        "mat",
        "coords",
        "points",
        "xs",
        "ys"
      ] ->
        true

      name in ["x", "y"] and
          String.contains?(doc_lower, [
            "sequence",
            "list",
            "data",
            "array",
            "vector",
            "iterable",
            "samples"
          ]) ->
        true

      name in ["x", "y"] and
          String.contains?(func_lower, [
            "correlation",
            "covariance",
            "regression",
            "trapz",
            "trapezoid"
          ]) ->
        true

      true ->
        false
    end
  end

  defp list_placeholder(name) do
    if name in ["dimensions", "shape"] do
      "[2, 2]"
    else
      "[1, 2, 3]"
    end
  end

  defp map_param?(name) do
    String.contains?(name, ["obj", "dict", "map", "mapping", "kwargs", "params", "options"])
  end

  defp bytes_param?(name, doc_lower, type_hint) do
    doc_mentions_bytes =
      String.contains?(doc_lower, ["bytes", "bytearray", "byte string", "bytes-like", "binary"])

    bytes_type_hint?(type_hint) or
      String.contains?(name, ["byte", "bytes", "byte_str"]) or
      (doc_mentions_bytes and bytes_param_name?(name))
  end

  defp param_bytes_conversion?(param, doc_lower, func_lower) do
    type = Map.get(param, "type", "")
    type_bytes = String.contains?(to_string(type), ["bytes", "bytearray"])
    name = String.downcase(param_name(param) || "")

    type_bytes or bytes_param?(name, doc_lower, type) or bytes_name_hint?(name, func_lower)
  end

  defp bytes_name_hint?(name, func_lower) do
    if bytes_param_name?(name) do
      if name in ["b", "bs", "s", "data"] do
        String.contains?(func_lower, ["encode", "decode", "encoding", "base", "binary"])
      else
        true
      end
    else
      false
    end
  end

  defp boolean_param?(name) do
    String.starts_with?(name, ["is_", "has_", "should_", "allow_"]) or
      name in ["flag", "enabled", "verbose"]
  end

  defp numeric_param?(name) do
    name in [
      "n",
      "x",
      "y",
      "z",
      "i",
      "j",
      "k",
      "m",
      "count",
      "size",
      "width",
      "height",
      "limit",
      "max",
      "min",
      "start",
      "end",
      "step",
      "index",
      "offset",
      "number",
      "num"
    ]
  end

  defp string_param?(name) do
    name in [
      "s",
      "str",
      "string",
      "text",
      "name",
      "title",
      "label",
      "repl",
      "sep",
      "delimiter",
      "prefix",
      "suffix",
      "format",
      "fmt",
      "url",
      "uri",
      "path",
      "file",
      "host",
      "user",
      "password",
      "query",
      "fragment",
      "attr",
      "field",
      "typename",
      "field_names",
      "method",
      "encoding",
      "charset",
      "version"
    ] or
      String.contains?(name, ["str", "text"])
  end

  defp validate_manifest(manifest_path, on_output) do
    on_output.("  → Validating manifest...\n")

    case Manifest.validate_file(manifest_path) do
      {:ok, _config} ->
        on_output.("  ✓ Manifest is valid\n")
        :ok

      {:error, errors} when is_list(errors) ->
        on_output.("  ✗ Validation errors:\n")
        Enum.each(errors, fn e -> on_output.("    - #{e}\n") end)
        {:error, {:validation_failed, errors}}

      {:error, reason} ->
        on_output.("  ✗ Validation failed: #{inspect(reason)}\n")
        {:error, {:validation_failed, reason}}
    end
  end

  defp default_output(text) do
    IO.write(text)
    :ok
  end
end
