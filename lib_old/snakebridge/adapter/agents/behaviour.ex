defmodule SnakeBridge.Adapter.Agents.Behaviour do
  @moduledoc """
  Behaviour for SnakeBridge adapter analysis agents.

  All agent implementations must implement this behaviour.
  """

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
  Analyzes a Python library and returns structured analysis.

  ## Parameters

  - `lib_path` - Absolute path to the Python library
  - `opts` - Options including:
    - `:max_functions` - Max functions to analyze (default: 20)
    - `:category` - Override category detection
    - `:timeout` - Analysis timeout

  ## Returns

  `{:ok, analysis_result}` or `{:error, reason}`
  """
  @callback analyze(lib_path :: String.t(), opts :: keyword()) ::
              {:ok, analysis_result()} | {:error, term()}
end
