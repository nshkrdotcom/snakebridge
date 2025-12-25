defmodule SnakeBridge.Adapter.Generator do
  @moduledoc """
  Generates SnakeBridge adapter files from analysis results.

  Produces:
  - JSON manifest file
  - Python bridge file (if needed)
  - Example Elixir script
  - Test file
  """

  require Logger

  @manifest_dir "priv/snakebridge/manifests"
  @bridge_dir "priv/python/bridges"
  @example_dir "examples"
  @test_dir "test/snakebridge"

  @type generation_result :: %{
          manifest_path: String.t(),
          bridge_path: String.t() | nil,
          example_path: String.t(),
          test_path: String.t()
        }

  @doc """
  Generates all adapter files from analysis results.

  ## Parameters

  - `analysis` - Analysis result from an agent
  - `opts` - Options
    - `:output_dir` - Base output directory (default: current directory)
    - `:skip_example` - Skip example generation
    - `:skip_test` - Skip test generation
    - `:skip_bridge` - Skip bridge even if needed

  ## Returns

  `{:ok, generation_result}` or `{:error, reason}`
  """
  @spec generate(map(), keyword()) :: {:ok, generation_result()} | {:error, term()}
  def generate(analysis, opts \\ []) do
    output_dir = Keyword.get(opts, :output_dir, File.cwd!())

    with {:ok, manifest_path} <- generate_manifest(analysis, output_dir),
         {:ok, bridge_path} <- maybe_generate_bridge(analysis, output_dir, opts),
         {:ok, example_path} <- maybe_generate_example(analysis, output_dir, opts),
         {:ok, test_path} <- maybe_generate_test(analysis, output_dir, opts) do
      {:ok,
       %{
         manifest_path: manifest_path,
         bridge_path: bridge_path,
         example_path: example_path,
         test_path: test_path
       }}
    end
  end

  @doc """
  Generates only the manifest file.
  """
  @spec generate_manifest(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_manifest(analysis, output_dir) do
    manifest = build_manifest(analysis)
    manifest_json = Jason.encode!(manifest, pretty: true)

    path = Path.join([output_dir, @manifest_dir, "#{analysis.name}.json"])

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, manifest_json) do
      Logger.info("Generated manifest: #{path}")
      {:ok, path}
    else
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  @doc """
  Generates a Python bridge file if needed.
  """
  @spec generate_bridge(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_bridge(analysis, output_dir) do
    bridge_code = build_bridge(analysis)
    path = Path.join([output_dir, @bridge_dir, "#{analysis.name}_bridge.py"])

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, bridge_code) do
      Logger.info("Generated bridge: #{path}")
      {:ok, path}
    else
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  # Private - Manifest building

  defp build_manifest(analysis) do
    functions =
      analysis.functions
      |> Enum.map(&build_manifest_function/1)

    %{
      "name" => analysis.name,
      "python_module" => analysis.python_module,
      "python_path_prefix" =>
        if(analysis.needs_bridge,
          do: "bridges.#{analysis.name}_bridge",
          else: analysis.python_module
        ),
      "version" => analysis.version,
      "category" => analysis.category,
      "elixir_module" => "SnakeBridge.#{elixir_module_name(analysis.name)}",
      "pypi_package" => analysis.pypi_package,
      "description" => analysis.description,
      "status" => "experimental",
      "types" => analysis.types,
      "functions" => functions
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp build_manifest_function(func) do
    args =
      (func["args"] || [])
      |> Enum.map(fn arg ->
        case arg do
          %{"name" => name} -> name
          name when is_binary(name) -> name
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    returns =
      case func["returns"] do
        %{"type" => type} -> type
        type when is_binary(type) -> type
        _ -> "any"
      end

    entry = %{
      "name" => func["name"],
      "args" => args,
      "returns" => returns
    }

    entry =
      if func["doc"] && func["doc"] != "" do
        Map.put(entry, "doc", func["doc"])
      else
        entry
      end

    entry
  end

  defp elixir_module_name(name) do
    name
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end

  # Private - Bridge building

  defp maybe_generate_bridge(analysis, output_dir, opts) do
    if analysis.needs_bridge and not Keyword.get(opts, :skip_bridge, false) do
      generate_bridge(analysis, output_dir)
    else
      {:ok, nil}
    end
  end

  defp build_bridge(analysis) do
    imports = build_bridge_imports(analysis)
    functions = build_bridge_functions(analysis)

    """
    \"\"\"
    SnakeBridge bridge for #{analysis.name}.

    This bridge provides JSON-serializable wrappers around #{analysis.python_module} functions.
    Generated automatically - review and adjust as needed.
    \"\"\"

    #{imports}

    #{functions}
    """
  end

  defp build_bridge_imports(analysis) do
    """
    import json
    from typing import Any, Dict, List, Optional, Union

    try:
        import #{analysis.python_module}
    except ImportError:
        raise ImportError("#{analysis.pypi_package} is not installed. Run: pip install #{analysis.pypi_package}")
    """
  end

  defp build_bridge_functions(analysis) do
    analysis.functions
    |> Enum.map(&build_single_bridge_function(&1, analysis))
    |> Enum.join("\n\n")
  end

  defp build_single_bridge_function(func, analysis) do
    name = func["name"]
    args = func["args"] || []

    arg_names =
      args
      |> Enum.map(fn
        %{"name" => n} -> n
        n when is_binary(n) -> n
      end)

    arg_str = Enum.join(arg_names, ", ")

    python_path = func["python_path"] || "#{analysis.python_module}.#{name}"

    """
    def #{name}(#{arg_str}):
        \"\"\"
        Wrapper for #{python_path}.
        #{func["doc"] || ""}
        \"\"\"
        try:
            result = #{python_path}(#{arg_str})
            return _serialize(result)
        except Exception as e:
            return {"error": str(e), "type": type(e).__name__}


    def _serialize(obj):
        \"\"\"Convert Python objects to JSON-serializable form.\"\"\"
        if obj is None:
            return None
        if isinstance(obj, (str, int, float, bool)):
            return obj
        if isinstance(obj, (list, tuple)):
            return [_serialize(item) for item in obj]
        if isinstance(obj, dict):
            return {str(k): _serialize(v) for k, v in obj.items()}
        # Custom object - convert to string representation
        return str(obj)
    """
  end

  # Private - Example building

  defp maybe_generate_example(analysis, output_dir, opts) do
    if Keyword.get(opts, :skip_example, false) do
      {:ok, nil}
    else
      generate_example(analysis, output_dir)
    end
  end

  defp generate_example(analysis, output_dir) do
    example_code = build_example(analysis)
    path = Path.join([output_dir, @example_dir, "manifest_#{analysis.name}.exs"])

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, example_code) do
      Logger.info("Generated example: #{path}")
      {:ok, path}
    else
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  defp build_example(analysis) do
    module_name = "SnakeBridge.#{elixir_module_name(analysis.name)}"
    first_func = List.first(analysis.functions)

    example_call =
      if first_func do
        args = first_func["args"] || []

        arg_map =
          args
          |> Enum.map(fn
            %{"name" => n, "type" => t} -> {n, example_value(t)}
            %{"name" => n} -> {n, "\"example\""}
            n when is_binary(n) -> {n, "\"example\""}
          end)
          |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
          |> Enum.join(", ")

        """
        # Example: #{first_func["name"]}
        {:ok, result} = #{module_name}.#{first_func["name"]}(%{#{arg_map}})
        IO.inspect(result, label: "#{first_func["name"]} result")
        """
      else
        "# No functions available for example"
      end

    """
    #!/usr/bin/env elixir
    # Example usage of #{module_name}
    #
    # Run with: mix run #{@example_dir}/manifest_#{analysis.name}.exs
    #
    # Prerequisites:
    #   1. Add to config: config :snakebridge, load: [:#{analysis.name}]
    #   2. Install Python package: pip install #{analysis.pypi_package}

    # Ensure SnakeBridge is started
    Application.ensure_all_started(:snakebridge)

    # Wait for pool to be ready
    Process.sleep(1000)

    alias #{module_name}

    IO.puts("\\n=== #{analysis.name} Examples ===\\n")

    #{example_call}

    IO.puts("\\nDone!")
    """
  end

  defp example_value("string"), do: "\"example\""
  defp example_value("integer"), do: "42"
  defp example_value("float"), do: "3.14"
  defp example_value("boolean"), do: "true"
  defp example_value("list"), do: "[1, 2, 3]"
  defp example_value("map"), do: "%{key: \"value\"}"
  defp example_value(_), do: "\"example\""

  # Private - Test building

  defp maybe_generate_test(analysis, output_dir, opts) do
    if Keyword.get(opts, :skip_test, false) do
      {:ok, nil}
    else
      generate_test(analysis, output_dir)
    end
  end

  defp generate_test(analysis, output_dir) do
    test_code = build_test(analysis)
    path = Path.join([output_dir, @test_dir, "#{analysis.name}_test.exs"])

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, test_code) do
      Logger.info("Generated test: #{path}")
      {:ok, path}
    else
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  defp build_test(analysis) do
    module_name = "SnakeBridge.#{elixir_module_name(analysis.name)}"

    test_cases =
      analysis.functions
      |> Enum.take(5)
      |> Enum.map(&build_test_case(&1, module_name))
      |> Enum.join("\n\n")

    """
    defmodule #{module_name}Test do
      @moduledoc \"\"\"
      Tests for #{module_name}.

      Run with: mix test test/snakebridge/#{analysis.name}_test.exs
      For real Python tests: mix test test/snakebridge/#{analysis.name}_test.exs --only real_python
      \"\"\"

      use ExUnit.Case, async: false

      alias #{module_name}

      @moduletag :real_python

      setup_all do
        Application.ensure_all_started(:snakebridge)
        # Give pool time to start
        Process.sleep(500)
        :ok
      end

    #{test_cases}
    end
    """
  end

  defp build_test_case(func, module_name) do
    name = func["name"]
    args = func["args"] || []

    arg_map =
      args
      |> Enum.map(fn
        %{"name" => n, "type" => t} -> {n, test_value(t)}
        %{"name" => n} -> {n, "\"test\""}
        n when is_binary(n) -> {n, "\"test\""}
      end)
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join(", ")

    """
      describe "#{name}/1" do
        test "returns ok tuple on valid input" do
          result = #{module_name}.#{name}(%{#{arg_map}})
          assert match?({:ok, _}, result) or match?({:error, _}, result)
        end
      end
    """
  end

  defp test_value("string"), do: "\"test\""
  defp test_value("integer"), do: "1"
  defp test_value("float"), do: "1.0"
  defp test_value("boolean"), do: "true"
  defp test_value("list"), do: "[]"
  defp test_value("map"), do: "%{}"
  defp test_value(_), do: "\"test\""
end
