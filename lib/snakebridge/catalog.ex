defmodule SnakeBridge.Catalog do
  @moduledoc """
  Catalog of Python libraries with tested SnakeBridge integrations.

  Provides a curated list of Python packages with:
  - Package metadata (PyPI name, version)
  - Integration status (tested, beta, experimental)
  - Adapter specifications (generic or specialized)
  - Setup requirements (API keys, dependencies)

  ## Usage

      # List all cataloged libraries
      SnakeBridge.Catalog.list()

      # Get specific library
      SnakeBridge.Catalog.get(:genai)

      # Filter by category
      SnakeBridge.Catalog.by_category(:llm)

      # Get streaming libraries
      SnakeBridge.Catalog.streaming_libraries()

      # Get install command
      {:ok, cmd} = SnakeBridge.Catalog.install_command(:genai)
      # => "pip install google-genai==0.3.0"
  """

  @type library_entry :: %{
          # Identity
          name: atom(),
          description: String.t(),
          category: atom(),

          # Python package info
          pypi_package: String.t() | nil,
          import_name: String.t(),
          version: String.t(),
          python_requires: String.t(),

          # SnakeBridge integration
          adapter: :generic | :specialized,
          adapter_module: String.t() | nil,
          adapter_class: String.t() | nil,

          # Capabilities
          supports_streaming: boolean(),
          supports_classes: boolean(),
          supports_functions: boolean(),

          # Requirements
          requires_env: [String.t()],
          dependencies: [String.t()],

          # Status
          status: :tested | :beta | :experimental,
          tested_version: String.t(),
          last_updated: Date.t()
        }

  @catalog [
    # === LLMs / Generative AI ===
    %{
      name: :genai,
      description: "Google Gemini AI with streaming text generation",
      category: :llm,
      pypi_package: "google-genai",
      import_name: "genai",
      version: "0.3.0",
      python_requires: ">=3.9",
      adapter: :specialized,
      adapter_module: "adapters.genai.adapter",
      adapter_class: "GenAIAdapter",
      supports_streaming: true,
      supports_classes: true,
      supports_functions: true,
      requires_env: ["GEMINI_API_KEY"],
      dependencies: [],
      status: :tested,
      tested_version: "0.3.0",
      last_updated: ~D[2025-10-26]
    },

    # === Scientific Computing ===
    %{
      name: :numpy,
      description: "Numerical computing with N-dimensional arrays and mathematical functions",
      category: :scientific,
      pypi_package: "numpy",
      import_name: "numpy",
      version: "2.3.3",
      python_requires: ">=3.9",
      adapter: :generic,
      adapter_module: nil,
      adapter_class: nil,
      supports_streaming: false,
      supports_classes: true,
      supports_functions: true,
      requires_env: [],
      dependencies: [],
      status: :tested,
      tested_version: "2.3.3",
      last_updated: ~D[2025-10-26]
    },

    # === HTTP / Networking ===
    %{
      name: :requests,
      description: "HTTP library for Python with streaming download support",
      category: :http,
      pypi_package: "requests",
      import_name: "requests",
      version: "2.32.5",
      python_requires: ">=3.8",
      adapter: :generic,
      adapter_module: nil,
      adapter_class: nil,
      supports_streaming: true,
      supports_classes: false,
      supports_functions: true,
      requires_env: [],
      dependencies: ["urllib3>=2.0", "certifi>=2020.06"],
      status: :tested,
      tested_version: "2.32.5",
      last_updated: ~D[2025-10-26]
    },

    # === Built-in (No Install) ===
    %{
      name: :json,
      description: "Python's built-in JSON encoder/decoder",
      category: :serialization,
      pypi_package: nil,
      import_name: "json",
      version: "2.0.9",
      python_requires: ">=3.8",
      adapter: :generic,
      adapter_module: nil,
      adapter_class: nil,
      supports_streaming: false,
      supports_classes: true,
      supports_functions: true,
      requires_env: [],
      dependencies: [],
      status: :tested,
      tested_version: "2.0.9",
      last_updated: ~D[2025-10-26]
    }
  ]

  @doc """
  List all cataloged Python libraries.
  """
  @spec list() :: [library_entry()]
  def list, do: @catalog

  @doc """
  Get library entry by name.
  """
  @spec get(atom()) :: library_entry() | nil
  def get(library_name) when is_atom(library_name) do
    Enum.find(@catalog, &(&1.name == library_name))
  end

  @doc """
  List libraries by category (:llm, :scientific, :http, etc.).
  """
  @spec by_category(atom()) :: [library_entry()]
  def by_category(category) when is_atom(category) do
    Enum.filter(@catalog, &(&1.category == category))
  end

  @doc """
  List libraries that support streaming.
  """
  @spec streaming_libraries() :: [library_entry()]
  def streaming_libraries do
    Enum.filter(@catalog, &(&1.supports_streaming == true))
  end

  @doc """
  Check if library uses specialized adapter.
  """
  @spec specialized?(atom()) :: boolean()
  def specialized?(library_name) do
    case get(library_name) do
      nil -> false
      entry -> entry.adapter == :specialized
    end
  end

  @doc """
  Get pip install command for a library.

  Returns command with pinned version from catalog.
  """
  @spec install_command(atom()) :: {:ok, String.t()} | {:error, :not_in_catalog}
  def install_command(library_name) do
    case get(library_name) do
      nil ->
        {:error, :not_in_catalog}

      %{pypi_package: nil} ->
        {:ok, "# Built-in module - no installation needed"}

      entry ->
        cmd = "pip install #{entry.pypi_package}==#{entry.version}"
        {:ok, cmd}
    end
  end

  @doc """
  Get adapter configuration for Snakepit.

  Returns configuration for starting Snakepit with correct adapter.
  """
  @spec adapter_config(atom()) :: {:ok, map()} | {:error, :not_in_catalog}
  def adapter_config(library_name) do
    case get(library_name) do
      nil ->
        {:error, :not_in_catalog}

      entry ->
        config = %{
          library: library_name,
          use_specialized: entry.adapter == :specialized,
          python_module: entry.adapter_module || "snakebridge_adapter.adapter",
          python_class: entry.adapter_class || "SnakeBridgeAdapter",
          requires_env: entry.requires_env,
          supports_streaming: entry.supports_streaming
        }

        {:ok, config}
    end
  end
end
