defmodule SnakeBridge.Adapter.AgentOrchestrator do
  @moduledoc """
  Orchestrates AI agents for Python library analysis.

  Automatically detects available AI SDKs (claude_agent_sdk, codex_sdk)
  and uses the best available option. Falls back to heuristic-only
  analysis if no AI SDK is available.

  ## SDK Priority

  1. User-specified via `--agent` flag
  2. claude_agent_sdk (if available)
  3. codex_sdk (if available)
  4. Fallback heuristic analysis
  """

  require Logger

  alias SnakeBridge.Adapter.Agents.{ClaudeAgent, CodexAgent, FallbackAgent}

  @type agent_type :: :claude | :codex | :fallback
  @type analysis_result :: %{
          name: String.t(),
          description: String.t(),
          category: String.t(),
          pypi_package: String.t(),
          python_module: String.t(),
          version: String.t() | nil,
          functions: [map()],
          types: map(),
          needs_bridge: boolean(),
          bridge_functions: [map()],
          example_usage: String.t() | nil,
          notes: [String.t()]
        }

  @doc """
  Detects which AI SDKs are available.

  Returns a list of available agent types in priority order.
  """
  @spec available_agents() :: [agent_type()]
  def available_agents do
    agents = []

    agents =
      if claude_available?() do
        [:claude | agents]
      else
        agents
      end

    agents =
      if codex_available?() do
        [:codex | agents]
      else
        agents
      end

    # Fallback is always available
    Enum.reverse(agents) ++ [:fallback]
  end

  @doc """
  Returns the best available agent type.
  """
  @spec best_agent() :: agent_type()
  def best_agent do
    available_agents() |> List.first()
  end

  @doc """
  Checks if a specific agent type is available.
  """
  @spec agent_available?(agent_type()) :: boolean()
  def agent_available?(:claude), do: claude_available?()
  def agent_available?(:codex), do: codex_available?()
  def agent_available?(:fallback), do: true

  @doc """
  Analyzes a Python library using the specified or best available agent.

  ## Parameters

  - `lib_path` - Path to the cloned Python library
  - `opts` - Options
    - `:agent` - Force specific agent (:claude, :codex, :fallback)
    - `:max_functions` - Maximum functions to include (default: 20)
    - `:category` - Override category detection
    - `:timeout` - Analysis timeout in ms (default: 120_000)

  ## Returns

  `{:ok, analysis_result}` or `{:error, reason}`
  """
  @spec analyze(String.t(), keyword()) :: {:ok, analysis_result()} | {:error, term()}
  def analyze(lib_path, opts \\ []) do
    agent = Keyword.get(opts, :agent) || best_agent()
    timeout = Keyword.get(opts, :timeout, 120_000)

    unless agent_available?(agent) do
      {:error, {:agent_unavailable, agent}}
    else
      Logger.info("Analyzing library with #{agent} agent: #{lib_path}")

      task =
        Task.async(fn ->
          do_analyze(agent, lib_path, opts)
        end)

      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} -> result
        nil -> {:error, :timeout}
      end
    end
  end

  @doc """
  Returns human-readable status of available agents.
  """
  @spec status() :: map()
  def status do
    %{
      claude: %{
        available: claude_available?(),
        module: ClaudeAgent,
        description: "Claude Code via claude_agent_sdk"
      },
      codex: %{
        available: codex_available?(),
        module: CodexAgent,
        description: "OpenAI Codex via codex_sdk"
      },
      fallback: %{
        available: true,
        module: FallbackAgent,
        description: "Heuristic-only analysis (no AI)"
      },
      best: best_agent()
    }
  end

  # Private functions

  defp do_analyze(:claude, lib_path, opts) do
    ClaudeAgent.analyze(lib_path, opts)
  end

  defp do_analyze(:codex, lib_path, opts) do
    CodexAgent.analyze(lib_path, opts)
  end

  defp do_analyze(:fallback, lib_path, opts) do
    FallbackAgent.analyze(lib_path, opts)
  end

  defp claude_available? do
    Code.ensure_loaded?(ClaudeAgentSDK) and
      function_exported?(ClaudeAgentSDK, :query, 2)
  end

  defp codex_available? do
    Code.ensure_loaded?(Codex) and
      function_exported?(Codex, :start_thread, 0)
  end
end
