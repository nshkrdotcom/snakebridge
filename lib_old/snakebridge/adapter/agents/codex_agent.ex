defmodule SnakeBridge.Adapter.Agents.CodexAgent do
  @moduledoc """
  AI agent using OpenAI Codex via codex_sdk.

  Performs deep analysis of Python libraries using Codex's
  code understanding capabilities.
  """

  require Logger

  @behaviour SnakeBridge.Adapter.Agents.Behaviour

  @analysis_prompt """
  Analyze this Python library for SnakeBridge (Elixir-Python bridge) integration.

  CRITICAL: Only STATELESS functions work. No file I/O, no network, no GUI, no class instances.

  Respond with ONLY a JSON object (no markdown):

  {
    "name": "library_name",
    "description": "One-line description",
    "category": "math|text|data|ml|validation|utilities",
    "pypi_package": "package-name",
    "python_module": "import_name",
    "version": "version or null",
    "functions": [
      {
        "name": "func_name",
        "python_path": "module.func",
        "args": [{"name": "x", "type": "string", "required": true}],
        "returns": {"type": "string"},
        "doc": "Description",
        "needs_bridge": false
      }
    ],
    "types": {"arg_name": "type"},
    "needs_bridge": false,
    "bridge_functions": [],
    "notes": []
  }

  Type mappings: str→string, int→integer, float→float, bool→boolean, list→list, dict→map

  Select TOP {{MAX_FUNCTIONS}} most useful stateless functions.
  """

  @impl true
  def analyze(lib_path, opts \\ []) do
    max_functions = Keyword.get(opts, :max_functions, 20)

    prompt =
      @analysis_prompt
      |> String.replace("{{MAX_FUNCTIONS}}", to_string(max_functions))

    context = build_context(lib_path)

    full_prompt = """
    #{prompt}

    Library at: #{lib_path}

    Key files:
    #{context}
    """

    case query_codex(full_prompt, lib_path) do
      {:ok, response} ->
        parse_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_codex(prompt, working_dir) do
    if Code.ensure_loaded?(Codex) do
      Logger.info("Querying Codex for library analysis...")

      try do
        # Start a Codex thread
        {:ok, thread} = apply(Codex, :start_thread, [[cwd: working_dir]])

        # Run the analysis
        case apply(Codex.Thread, :run, [thread, prompt]) do
          {:ok, result} ->
            text = extract_response_text(result)
            {:ok, text}

          {:error, reason} ->
            {:error, {:codex_error, reason}}
        end
      rescue
        e ->
          {:error, {:codex_exception, Exception.message(e)}}
      end
    else
      {:error, :codex_sdk_not_loaded}
    end
  end

  defp extract_response_text(result) when is_map(result) do
    result[:final_response] ||
      result["final_response"] ||
      result[:text] ||
      result["text"] ||
      inspect(result)
  end

  defp extract_response_text(result) when is_binary(result), do: result
  defp extract_response_text(result), do: inspect(result)

  defp build_context(lib_path) do
    files = ["README.md", "README.rst", "pyproject.toml", "setup.py"]

    files
    |> Enum.map(&Path.join(lib_path, &1))
    |> Enum.filter(&File.exists?/1)
    |> Enum.map(fn path ->
      case File.read(path) do
        {:ok, content} ->
          name = Path.basename(path)
          truncated = String.slice(content, 0, 2000)
          "=== #{name} ===\n#{truncated}"

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp parse_response(response) do
    json_text =
      response
      |> String.replace(~r/```json\s*/, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(json_text) do
      {:ok, data} ->
        {:ok, normalize_analysis(data)}

      {:error, _} ->
        case Regex.run(~r/\{[\s\S]*\}/, response) do
          [json] ->
            case Jason.decode(json) do
              {:ok, data} -> {:ok, normalize_analysis(data)}
              {:error, reason} -> {:error, {:json_parse_error, reason}}
            end

          nil ->
            {:error, {:no_json_in_response, response}}
        end
    end
  end

  defp normalize_analysis(data) do
    %{
      name: data["name"] || "unknown",
      description: data["description"] || "",
      category: data["category"] || "utilities",
      pypi_package: data["pypi_package"] || data["name"],
      python_module: data["python_module"] || data["name"],
      version: data["version"],
      functions: data["functions"] || [],
      types: data["types"] || %{},
      needs_bridge: data["needs_bridge"] || false,
      bridge_functions: data["bridge_functions"] || [],
      example_usage: data["example_usage"],
      notes: data["notes"] || []
    }
  end
end
