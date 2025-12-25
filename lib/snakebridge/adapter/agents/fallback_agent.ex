defmodule SnakeBridge.Adapter.Agents.FallbackAgent do
  @moduledoc """
  Heuristic-only analysis agent (no AI required).

  Uses Python introspection via Snakepit and heuristics
  to analyze libraries when no AI SDK is available.
  """

  require Logger

  @behaviour SnakeBridge.Adapter.Agents.Behaviour

  alias SnakeBridge.Adapter.Fetcher

  # Patterns indicating stateful/unsafe functions
  @exclude_patterns ~w(
    read write save load open close file path dir mkdir rmdir
    http socket connect request fetch download upload
    db sql query cursor execute
    plot show render display gui window
    stdin stdout stderr input print
    thread process fork exec spawn
    eval compile pickle marshal
    __init__ __new__ __del__ __enter__ __exit__
    _private
  )

  # Patterns indicating good stateless functions
  @include_patterns ~w(
    parse convert transform encode decode
    validate check verify is_ has_
    format to_ from_ as_
    calculate compute solve
    extract split join
    normalize clean sanitize
  )

  @impl true
  def analyze(lib_path, opts \\ []) do
    max_functions = Keyword.get(opts, :max_functions, 20)
    category = Keyword.get(opts, :category)

    Logger.info("Running heuristic analysis on: #{lib_path}")

    with {:ok, metadata} <- Fetcher.detect_python_project(lib_path),
         {:ok, functions} <- discover_functions(lib_path, metadata),
         selected <- select_best_functions(functions, max_functions) do
      {:ok,
       %{
         name: metadata.module_name || Path.basename(lib_path),
         description: metadata.description || "Python library",
         category: category || infer_category(lib_path, metadata),
         pypi_package: metadata.module_name || Path.basename(lib_path),
         python_module: metadata.module_name || Path.basename(lib_path),
         version: metadata.version,
         functions: format_functions(selected, metadata.module_name),
         types: extract_types(selected),
         needs_bridge: needs_bridge?(selected),
         bridge_functions: bridge_candidates(selected),
         example_usage: nil,
         notes: [
           "Generated via heuristic analysis (no AI)",
           "Review and adjust function selection manually"
         ]
       }}
    end
  end

  defp discover_functions(lib_path, metadata) do
    module_name = metadata.module_name || Path.basename(lib_path)

    # Try Snakepit introspection first
    case try_snakepit_discovery(module_name) do
      {:ok, functions} ->
        {:ok, functions}

      {:error, _} ->
        # Fall back to static analysis
        static_discover(lib_path, module_name)
    end
  end

  defp try_snakepit_discovery(module_name) do
    if Code.ensure_loaded?(SnakeBridge.Discovery) do
      case apply(SnakeBridge.Discovery, :discover, [module_name, [depth: 1]]) do
        {:ok, schema} ->
          functions =
            schema
            |> Map.get("functions", %{})
            |> Enum.map(fn {name, desc} ->
              %{
                name: name,
                doc: Map.get(desc, "docstring", ""),
                params: Map.get(desc, "parameters", []),
                return_type: Map.get(desc, "return_type"),
                module_path: module_name
              }
            end)

          {:ok, functions}

        error ->
          error
      end
    else
      {:error, :snakepit_not_available}
    end
  end

  defp static_discover(lib_path, module_name) do
    # Find Python files and extract function signatures
    python_files = find_python_files(lib_path)

    functions =
      python_files
      |> Enum.flat_map(&extract_functions_from_file(&1, lib_path))
      |> Enum.map(fn f -> Map.put(f, :module_path, module_name) end)

    {:ok, functions}
  end

  defp find_python_files(lib_path) do
    case File.ls(lib_path) do
      {:ok, entries} ->
        entries
        |> Enum.flat_map(fn entry ->
          full_path = Path.join(lib_path, entry)

          cond do
            File.dir?(full_path) and not String.starts_with?(entry, ".") and
                entry not in ["test", "tests", "docs", "examples", "__pycache__"] ->
              find_python_files(full_path)

            String.ends_with?(entry, ".py") and not String.starts_with?(entry, "_") ->
              [full_path]

            true ->
              []
          end
        end)

      _ ->
        []
    end
  end

  defp extract_functions_from_file(file_path, lib_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Simple regex to find function definitions
        regex = ~r/^def\s+([a-z_][a-z0-9_]*)\s*\(([^)]*)\)\s*(?:->([^:]+))?:/m

        Regex.scan(regex, content)
        |> Enum.map(fn
          [_, name, params, return_type] ->
            %{
              name: name,
              doc: extract_docstring(content, name),
              params: parse_params(params),
              return_type: parse_return_type(return_type),
              file_path: Path.relative_to(file_path, lib_path)
            }

          [_, name, params] ->
            %{
              name: name,
              doc: extract_docstring(content, name),
              params: parse_params(params),
              return_type: nil,
              file_path: Path.relative_to(file_path, lib_path)
            }
        end)
        |> Enum.reject(fn f -> excluded?(f.name) end)

      _ ->
        []
    end
  end

  defp extract_docstring(content, func_name) do
    # Look for docstring after function definition
    regex =
      ~r/def\s+#{Regex.escape(func_name)}\s*\([^)]*\)[^:]*:\s*\n\s*(?:'''|""")([^'"]+)(?:'''|""")/

    case Regex.run(regex, content) do
      [_, docstring] -> String.trim(docstring) |> String.split("\n") |> List.first()
      nil -> ""
    end
  end

  defp parse_params(params_str) do
    params_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "self", "cls", "*args", "**kwargs"]))
    |> Enum.map(fn param ->
      # Handle type annotations: param: type = default
      case Regex.run(~r/^([a-z_][a-z0-9_]*)(?:\s*:\s*([^=]+))?(?:\s*=\s*(.+))?$/i, param) do
        [_, name, type, default] ->
          %{name: name, type: python_to_elixir_type(type), required: is_nil(default)}

        [_, name, type] ->
          %{name: name, type: python_to_elixir_type(type), required: true}

        [_, name] ->
          %{name: name, type: "any", required: true}

        nil ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_return_type(nil), do: nil
  defp parse_return_type(type_str), do: python_to_elixir_type(String.trim(type_str))

  defp python_to_elixir_type(nil), do: "any"
  defp python_to_elixir_type(""), do: "any"

  defp python_to_elixir_type(type) do
    type = String.trim(type) |> String.downcase()

    cond do
      String.contains?(type, "str") -> "string"
      String.contains?(type, "int") -> "integer"
      String.contains?(type, "float") -> "float"
      String.contains?(type, "bool") -> "boolean"
      String.contains?(type, "list") -> "list"
      String.contains?(type, "dict") -> "map"
      String.contains?(type, "none") -> "nil"
      String.contains?(type, "optional") -> "any"
      true -> "any"
    end
  end

  defp excluded?(name) do
    name_lower = String.downcase(name)

    String.starts_with?(name, "_") or
      Enum.any?(@exclude_patterns, &String.contains?(name_lower, &1))
  end

  defp select_best_functions(functions, max) do
    functions
    |> Enum.map(fn f -> {f, score_function(f)} end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.take(max)
    |> Enum.map(fn {f, _} -> f end)
  end

  defp score_function(func) do
    name = func.name |> String.downcase()
    doc = func.doc || ""
    params = func.params || []

    # Base score
    score = 0

    # Bonus for matching good patterns
    pattern_bonus =
      @include_patterns
      |> Enum.count(&String.contains?(name, &1))
      |> Kernel.*(2)

    # Bonus for having documentation
    doc_bonus = if String.length(doc) > 10, do: 3, else: 0

    # Bonus for reasonable param count (2-4 is ideal)
    param_bonus =
      case length(params) do
        n when n in 1..4 -> 2
        n when n in 5..6 -> 1
        _ -> 0
      end

    # Bonus for type hints
    type_bonus =
      params
      |> Enum.count(fn p -> p[:type] && p[:type] != "any" end)

    score + pattern_bonus + doc_bonus + param_bonus + type_bonus
  end

  defp format_functions(functions, module_name) do
    Enum.map(functions, fn f ->
      %{
        "name" => f.name,
        "python_path" => build_python_path(f, module_name),
        "args" =>
          Enum.map(f.params || [], fn p ->
            %{
              "name" => p.name,
              "type" => p[:type] || "any",
              "required" => p[:required] != false
            }
          end),
        "returns" => %{"type" => f.return_type || "any"},
        "doc" => f.doc
      }
    end)
  end

  defp build_python_path(func, module_name) do
    if func[:file_path] do
      # Convert file path to module path
      mod_path =
        func.file_path
        |> String.replace(~r/\.py$/, "")
        |> String.replace("/", ".")

      "#{mod_path}.#{func.name}"
    else
      "#{module_name}.#{func.name}"
    end
  end

  defp extract_types(functions) do
    functions
    |> Enum.flat_map(fn f ->
      (f.params || [])
      |> Enum.map(fn p -> {p.name, p[:type] || "any"} end)
    end)
    |> Enum.into(%{})
  end

  defp needs_bridge?(functions) do
    Enum.any?(functions, fn f ->
      return_type = f.return_type || ""
      String.contains?(return_type, ["object", "class", "instance"])
    end)
  end

  defp bridge_candidates(functions) do
    functions
    |> Enum.filter(fn f ->
      return_type = f.return_type || ""
      String.contains?(return_type, ["object", "class", "instance"])
    end)
    |> Enum.map(& &1.name)
  end

  defp infer_category(lib_path, _metadata) do
    # Read README to infer category
    readme_path = Path.join(lib_path, "README.md")

    content =
      case File.read(readme_path) do
        {:ok, c} -> String.downcase(c)
        _ -> ""
      end

    cond do
      String.contains?(content, ["math", "symbolic", "algebra", "calculus"]) -> "math"
      String.contains?(content, ["nlp", "text", "language", "parse", "tokenize"]) -> "text"
      String.contains?(content, ["data", "dataframe", "csv", "pandas"]) -> "data"
      String.contains?(content, ["machine learning", "ml", "neural", "model"]) -> "ml"
      String.contains?(content, ["valid", "phone", "email", "check"]) -> "validation"
      true -> "utilities"
    end
  end
end
