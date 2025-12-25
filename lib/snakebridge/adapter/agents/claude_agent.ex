defmodule SnakeBridge.Adapter.Agents.ClaudeAgent do
  @moduledoc """
  AI agent using Claude Code via claude_agent_sdk.

  Performs deep analysis of Python libraries using Claude's
  understanding of code patterns, documentation, and best practices.
  """

  require Logger

  @behaviour SnakeBridge.Adapter.Agents.Behaviour

  @analysis_prompt """
  You are analyzing a Python library to create a SnakeBridge adapter for Elixir integration.

  SnakeBridge creates Elixir wrappers around Python libraries. It requires:
  1. A JSON manifest defining which functions to expose
  2. Optionally, a Python bridge for custom serialization

  **CRITICAL CONSTRAINTS for SnakeBridge:**
  - Only STATELESS functions work (no class instances, no file I/O, no network)
  - Functions must accept JSON-serializable inputs
  - Functions must return JSON-serializable outputs (or need a bridge)
  - Avoid: file operations, GUI, plotting, database, network, threading

  **Analyze this Python library and provide a JSON response with:**

  ```json
  {
    "name": "library_name",
    "description": "One-line description",
    "category": "math|text|data|ml|validation|utilities",
    "pypi_package": "pypi-package-name",
    "python_module": "import_name",
    "version": "detected version or null",
    "functions": [
      {
        "name": "function_name",
        "python_path": "module.submodule.function",
        "args": [
          {"name": "arg1", "type": "string", "required": true},
          {"name": "arg2", "type": "integer", "required": false, "default": 10}
        ],
        "returns": {"type": "string"},
        "doc": "Brief description",
        "stateless": true,
        "needs_bridge": false
      }
    ],
    "types": {
      "arg_name": "elixir_type_string"
    },
    "needs_bridge": false,
    "bridge_functions": [],
    "example_usage": "Brief Elixir usage example",
    "notes": ["Any important notes about the library"]
  }
  ```

  **Function Selection Criteria (pick the TOP functions):**
  1. Pure/stateless computation functions
  2. Well-documented with clear inputs/outputs
  3. Commonly used (check README examples)
  4. Simple parameter signatures (2-4 params ideal)

  **Type Mappings:**
  - str → string
  - int → integer
  - float → float
  - bool → boolean
  - list → list
  - dict → map
  - None → nil
  - Complex objects → need bridge (serialize to string/map)

  Library path: {{LIB_PATH}}
  Max functions to include: {{MAX_FUNCTIONS}}
  """

  @impl true
  def analyze(lib_path, opts \\ []) do
    max_functions = Keyword.get(opts, :max_functions, 20)

    prompt =
      @analysis_prompt
      |> String.replace("{{LIB_PATH}}", lib_path)
      |> String.replace("{{MAX_FUNCTIONS}}", to_string(max_functions))

    # Build context by reading key files
    context = build_context(lib_path)

    full_prompt = """
    #{prompt}

    **Library Contents:**

    #{context}

    Analyze this library and respond with ONLY the JSON object, no markdown code fences.
    """

    case query_claude(full_prompt, lib_path) do
      {:ok, response} ->
        parse_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_claude(prompt, working_dir) do
    if Code.ensure_loaded?(ClaudeAgentSDK) do
      Logger.info("Querying Claude for library analysis...")

      # Build Options struct properly - NO TOOLS, just respond with the context given
      options =
        struct(ClaudeAgentSDK.Options, %{
          cwd: working_dir,
          system_prompt:
            "You are a JSON generator. DO NOT use any tools. All context is provided in the prompt. Respond ONLY with a raw JSON object - no markdown, no code fences, no explanation.",
          max_turns: 1,
          allowed_tools: []
        })

      try do
        # Query returns a stream, collect it
        messages =
          ClaudeAgentSDK.query(prompt, options)
          |> Enum.to_list()

        # Check for errors
        error_msg =
          Enum.find(messages, fn msg ->
            msg.type == :result and msg.subtype != :success
          end)

        if error_msg do
          {:error, {:claude_error, error_msg}}
        else
          # Extract text from assistant messages
          text =
            messages
            |> Enum.filter(fn msg -> msg.type == :assistant end)
            |> Enum.map(&ClaudeAgentSDK.ContentExtractor.extract_text/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.join("\n")

          if text == "" do
            {:error, :no_response}
          else
            {:ok, text}
          end
        end
      rescue
        e ->
          {:error, {:claude_exception, Exception.message(e)}}
      end
    else
      {:error, :claude_sdk_not_loaded}
    end
  end

  defp build_context(lib_path) do
    files_to_read = [
      "README.md",
      "README.rst",
      "readme.md",
      "pyproject.toml",
      "setup.py"
    ]

    # Find main Python module
    main_modules = find_main_modules(lib_path)

    context_parts =
      files_to_read
      |> Enum.map(&Path.join(lib_path, &1))
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(fn path ->
        case File.read(path) do
          {:ok, content} ->
            "## #{Path.basename(path)}\n\n#{truncate(content, 3000)}"

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    module_parts =
      main_modules
      |> Enum.take(3)
      |> Enum.map(fn path ->
        case File.read(path) do
          {:ok, content} ->
            rel_path = Path.relative_to(path, lib_path)
            "## #{rel_path}\n\n```python\n#{truncate(content, 4000)}\n```"

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Enum.join(context_parts ++ module_parts, "\n\n---\n\n")
  end

  defp find_main_modules(lib_path) do
    # Look for __init__.py in top-level directories or main .py files
    case File.ls(lib_path) do
      {:ok, entries} ->
        entries
        |> Enum.flat_map(fn entry ->
          full_path = Path.join(lib_path, entry)

          cond do
            File.dir?(full_path) ->
              init_path = Path.join(full_path, "__init__.py")
              if File.exists?(init_path), do: [init_path], else: []

            String.ends_with?(entry, ".py") and entry not in ["setup.py", "conftest.py"] ->
              [full_path]

            true ->
              []
          end
        end)
        |> Enum.take(5)

      _ ->
        []
    end
  end

  defp truncate(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "\n... (truncated)"
    else
      text
    end
  end

  defp parse_response(response) do
    # Try to extract JSON from response
    json_text =
      response
      |> String.replace(~r/```json\s*/, "")
      |> String.replace(~r/```\s*$/, "")
      |> String.trim()

    case Jason.decode(json_text) do
      {:ok, data} ->
        {:ok, normalize_analysis(data)}

      {:error, _} ->
        # Try to find JSON object in response
        case Regex.run(~r/\{[\s\S]*\}/, response) do
          [json] ->
            case Jason.decode(json) do
              {:ok, data} -> {:ok, normalize_analysis(data)}
              {:error, reason} -> {:error, {:json_parse_error, reason, response}}
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
      functions: normalize_functions(data["functions"] || []),
      types: data["types"] || %{},
      needs_bridge: data["needs_bridge"] || false,
      bridge_functions: data["bridge_functions"] || [],
      example_usage: data["example_usage"],
      notes: data["notes"] || []
    }
  end

  defp normalize_functions(functions) when is_list(functions) do
    Enum.map(functions, fn f ->
      %{
        "name" => f["name"],
        "python_path" => f["python_path"] || f["name"],
        "args" => normalize_args(f["args"] || []),
        "returns" => f["returns"] || %{"type" => "any"},
        "doc" => f["doc"],
        "stateless" => f["stateless"] != false,
        "needs_bridge" => f["needs_bridge"] || false
      }
    end)
  end

  defp normalize_functions(_), do: []

  defp normalize_args(args) when is_list(args) do
    Enum.map(args, fn arg ->
      case arg do
        arg when is_binary(arg) ->
          %{"name" => arg, "type" => "any", "required" => true}

        arg when is_map(arg) ->
          %{
            "name" => arg["name"],
            "type" => arg["type"] || "any",
            "required" => arg["required"] != false,
            "default" => arg["default"]
          }

        _ ->
          %{"name" => "arg", "type" => "any", "required" => true}
      end
    end)
  end

  defp normalize_args(_), do: []
end
