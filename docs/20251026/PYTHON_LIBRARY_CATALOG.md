# SnakeBridge Python Library Catalog

**Purpose**: Ship optimized integrations for common Python libraries
**What It Is**: A manifest of Python packages with tested configurations, adapters, and examples

---

## Architecture

```
SnakeBridge Package
│
└── Python Library Catalog
    ├── Manifest (lib/snakebridge/catalog.ex)
    │   - Library metadata (name, version, pypi package)
    │   - Adapter configurations
    │   - Dependencies
    │   - Status (tested, beta, experimental)
    │
    ├── Specialized Adapters (optional optimizations)
    │   priv/python/adapters/
    │   ├── genai/           # google-genai 0.3.x
    │   ├── openai/          # openai 1.x (future)
    │   └── anthropic/       # anthropic 0.x (future)
    │
    └── Guides (HexDocs)
        guides/catalog/
        ├── 00_overview.md
        ├── genai.md
        └── ...
```

---

## Catalog Manifest Structure

**File**: `lib/snakebridge/catalog.ex`

```elixir
defmodule SnakeBridge.Catalog do
  @moduledoc """
  Catalog of tested Python library integrations.

  Provides:
  - Library metadata (package name, version, dependencies)
  - Tested configurations
  - Setup instructions
  - Adapter specifications
  """

  @type library_entry :: %{
          # Identity
          name: atom(),
          description: String.t(),
          category: atom(),

          # Python package info
          pypi_package: String.t(),
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
    # === LLMs / GenAI ===
    %{
      name: :genai,
      description: "Google Gemini AI with streaming text generation",
      category: :llm,

      # PyPI info
      pypi_package: "google-genai",
      import_name: "genai",
      version: "0.3.0",  # Latest as of 2025-10-26
      python_requires: ">=3.9",

      # SnakeBridge integration
      adapter: :specialized,
      adapter_module: "adapters.genai.adapter",
      adapter_class: "GenAIAdapter",

      # Capabilities
      supports_streaming: true,
      supports_classes: true,
      supports_functions: true,

      # Requirements
      requires_env: ["GEMINI_API_KEY"],
      dependencies: [],

      # Status
      status: :tested,
      tested_version: "0.3.0",
      last_updated: ~D[2025-10-26]
    },

    # === Scientific Computing ===
    %{
      name: :numpy,
      description: "Numerical computing with N-dimensional arrays",
      category: :scientific,

      pypi_package: "numpy",
      import_name: "numpy",
      version: "2.3.3",
      python_requires: ">=3.9",

      # Uses generic adapter
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
      description: "HTTP library with streaming downloads",
      category: :http,

      pypi_package: "requests",
      import_name: "requests",
      version: "2.32.0",
      python_requires: ">=3.8",

      adapter: :generic,
      adapter_module: nil,
      adapter_class: nil,

      supports_streaming: true,  # Can stream downloads
      supports_classes: false,
      supports_functions: true,

      requires_env: [],
      dependencies: ["urllib3", "certifi"],

      status: :tested,
      tested_version: "2.32.0",
      last_updated: ~D[2025-10-26]
    }

    # Future entries:
    # - openai (LLM streaming)
    # - anthropic (Claude streaming)
    # - pandas (data frames)
    # - scipy (scientific computing)
    # - etc.
  ]

  @doc """
  List all cataloged Python libraries.

  Returns list of library entries with metadata.
  """
  def list do
    @catalog
  end

  @doc """
  Get library entry by name.
  """
  def get(library_name) when is_atom(library_name) do
    Enum.find(@catalog, &(&1.name == library_name))
  end

  @doc """
  List libraries by category.
  """
  def by_category(category) when is_atom(category) do
    Enum.filter(@catalog, &(&1.category == category))
  end

  @doc """
  List libraries that support streaming.
  """
  def streaming_libraries do
    Enum.filter(@catalog, &(&1.supports_streaming == true))
  end

  @doc """
  Check if library requires specialized adapter.
  """
  def specialized?(library_name) do
    case get(library_name) do
      nil -> false
      entry -> entry.adapter == :specialized
    end
  end

  @doc """
  Get installation command for a library.
  """
  def install_command(library_name) do
    case get(library_name) do
      nil ->
        {:error, :not_in_catalog}

      entry ->
        cmd = "pip install #{entry.pypi_package}==#{entry.version}"
        {:ok, cmd}
    end
  end

  @doc """
  Get adapter configuration for Snakepit.
  """
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
          requires_env: entry.requires_env
        }

        {:ok, config}
    end
  end
end
```

---

## API Design

### Query the Catalog

```elixir
# List all libraries
SnakeBridge.Catalog.list()
# => [%{name: :genai, pypi_package: "google-genai", version: "0.3.0", ...}, ...]

# Get specific library
SnakeBridge.Catalog.get(:genai)
# => %{name: :genai, pypi_package: "google-genai", ...}

# Get by category
SnakeBridge.Catalog.by_category(:llm)
# => [%{name: :genai, ...}, %{name: :openai, ...}]

# Get streaming libraries
SnakeBridge.Catalog.streaming_libraries()
# => [%{name: :genai, ...}, %{name: :requests, ...}]

# Get install command
SnakeBridge.Catalog.install_command(:genai)
# => {:ok, "pip install google-genai==0.3.0"}
```

### Use a Cataloged Library

```elixir
# Integrate with catalog entry
SnakeBridge.integrate_from_catalog(:genai)
# Automatically:
# - Checks GEMINI_API_KEY exists
# - Uses specialized GenAIAdapter if available
# - Falls back to generic if not
# - Generates modules

# Or manually
entry = SnakeBridge.Catalog.get(:genai)
# Install: run entry.install_command
# Integrate: SnakeBridge.integrate(entry.import_name)
```

---

## Mix Task Integration

```bash
# List catalog
mix snakebridge.catalog.list

# Show library details
mix snakebridge.catalog.info genai

# Install from catalog
mix snakebridge.catalog.install genai

# Integrate from catalog
mix snakebridge.catalog.integrate genai
```

---

## File Structure

```
lib/snakebridge/
├── catalog.ex                  # Main catalog (manifest)
├── adapter.ex                  # Behaviour (for specialized adapters)
└── adapters/
    └── genai.ex               # GenAI-specific helpers (optional)

priv/python/adapters/
├── genai/
│   ├── adapter.py             # GenAIAdapter (specialized)
│   ├── __init__.py
│   └── README.md
└── (future adapters...)

guides/catalog/
├── 00_overview.md
└── genai.md

test/catalog/
├── catalog_test.exs
└── genai_test.exs
```

---

Ready to implement?
