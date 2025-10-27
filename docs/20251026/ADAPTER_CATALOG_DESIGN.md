# SnakeBridge Adapter Catalog Design

**Purpose**: Ship library-specific adapters with SnakeBridge for common Python libraries
**Goal**: Reusable, documented, tested adapters available to all users

---

## Architecture

```
SnakeBridge Package
├── Generic Adapter (works with ANY library)
│   └── priv/python/snakebridge_adapter/adapter.py
│       - describe_library (introspection)
│       - call_python (execution)
│
└── Catalog Adapters (optimized for specific libraries)
    ├── priv/python/adapters/
    │   ├── genai/
    │   │   ├── adapter.py           # GenAI-specific adapter
    │   │   ├── __init__.py
    │   │   └── README.md            # Adapter docs
    │   ├── requests/
    │   │   ├── adapter.py           # HTTP streaming adapter
    │   │   └── ...
    │   └── pandas/
    │       └── ...
    │
    ├── lib/snakebridge/adapters/
    │   ├── catalog.ex               # Adapter registry
    │   ├── genai.ex                 # Elixir-side config/helpers
    │   └── ...
    │
    └── guides/adapters/
        ├── 00_adapter_catalog.md    # Overview (in HexDocs)
        ├── 01_genai.md              # GenAI guide
        ├── 02_requests.md           # Requests guide
        └── ...
```

---

## File Structure

### Python Adapter

**File**: `priv/python/adapters/genai/adapter.py`

```python
"""
GenAI Adapter for SnakeBridge

Provides optimized integration with Google's GenAI library:
- Streaming text generation
- Error handling for API keys
- Model configuration helpers

Install: pip install google-genai
"""

from snakepit_bridge.base_adapter_threaded import ThreadSafeAdapter, tool
import os

class GenAIAdapter(ThreadSafeAdapter):
    """
    Specialized adapter for Google GenAI library.

    Extends generic SnakeBridgeAdapter with:
    - Streaming support for generate_content_stream
    - API key validation
    - Model shortcuts (gemini-flash-lite-latest, etc.)
    """

    def __init__(self):
        super().__init__()
        self.client = None

    async def initialize(self):
        """Initialize GenAI client with API key."""
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY environment variable not set")

        import genai
        self.client = genai.Client(api_key=api_key)
        self.initialized = True

    @tool(description="Generate text with GenAI (streaming)", supports_streaming=True)
    def generate_text_stream(self, model: str, prompt: str) -> dict:
        """Stream text generation from Gemini."""
        if not self.client:
            return {"success": False, "error": "Client not initialized"}

        try:
            response = self.client.models.generate_content_stream(
                model=model,
                contents=prompt
            )

            # Return streaming response
            # Snakepit will handle chunk-by-chunk transmission
            for chunk in response:
                if chunk.text:
                    yield {"chunk": chunk.text}

            return {"success": True, "done": True}

        except Exception as e:
            return {"success": False, "error": str(e)}

    @tool(description="Generate text (non-streaming)")
    def generate_text(self, model: str, prompt: str) -> dict:
        """Non-streaming text generation."""
        # Implementation...
```

**File**: `priv/python/adapters/genai/__init__.py`
```python
from .adapter import GenAIAdapter
__all__ = ["GenAIAdapter"]
```

**File**: `priv/python/adapters/genai/README.md`
```markdown
# GenAI Adapter

Google GenAI integration for SnakeBridge with streaming support.

## Installation
pip install google-genai

## Configuration
export GEMINI_API_KEY="your-key-here"

## Features
- Streaming text generation
- Model shortcuts
- Error handling
```

---

### Elixir Catalog Entry

**File**: `lib/snakebridge/adapters/genai.ex`

```elixir
defmodule SnakeBridge.Adapters.GenAI do
  @moduledoc """
  Google GenAI adapter configuration for SnakeBridge.

  Provides streaming text generation with Gemini models.

  ## Installation

      # Add to config
      config :snakebridge, :adapter, :genai

  ## Example

      # Start with GenAI adapter
      SnakeBridge.use_adapter(:genai)

      # Stream text generation
      stream = GenAI.generate_stream(
        model: "gemini-flash-lite-latest",
        prompt: "Write a story"
      )

      for {:chunk, text} <- stream do
        IO.write(text)
      end

  ## Requirements

  - Python package: `google-genai`
  - Environment: `GEMINI_API_KEY`
  """

  @behaviour SnakeBridge.Adapter

  @impl true
  def adapter_config do
    %{
      python_module: "adapters.genai.adapter",
      python_class: "GenAIAdapter",
      name: :genai,
      description: "Google GenAI with streaming support",
      requires_packages: ["google-genai"],
      requires_env: ["GEMINI_API_KEY"],
      supports_streaming: true
    }
  end

  @impl true
  def setup_instructions do
    """
    1. Install: pip install google-genai
    2. Set API key: export GEMINI_API_KEY="your-key"
    3. Use: SnakeBridge.use_adapter(:genai)
    """
  end
end
```

---

### Adapter Catalog Registry

**File**: `lib/snakebridge/adapters/catalog.ex`

```elixir
defmodule SnakeBridge.Adapters.Catalog do
  @moduledoc """
  Registry of available SnakeBridge adapters.

  Adapters provide specialized integrations for specific Python libraries,
  with optimizations like streaming support, error handling, and helpers.

  ## Available Adapters

  - `:generic` - Works with any Python library (default)
  - `:genai` - Google GenAI with streaming (requires google-genai package)
  - `:requests` - HTTP client with progress (requires requests package)
  - `:pandas` - Data frames with chunking (requires pandas package)

  ## Usage

      # Use specific adapter
      SnakeBridge.use_adapter(:genai)

      # List available adapters
      SnakeBridge.Adapters.Catalog.list()

      # Get adapter info
      SnakeBridge.Adapters.Catalog.get(:genai)
  """

  @adapters [
    SnakeBridge.Adapters.GenAI,
    # Future: SnakeBridge.Adapters.Requests,
    # Future: SnakeBridge.Adapters.Pandas
  ]

  def list do
    Enum.map(@adapters, fn adapter_module ->
      config = adapter_module.adapter_config()
      %{
        name: config.name,
        description: config.description,
        module: adapter_module
      }
    end)
  end

  def get(adapter_name) do
    Enum.find(@adapters, fn adapter_module ->
      adapter_module.adapter_config().name == adapter_name
    end)
  end

  def adapter_config(adapter_name) do
    case get(adapter_name) do
      nil -> {:error, :adapter_not_found}
      adapter_module -> {:ok, adapter_module.adapter_config()}
    end
  end
end
```

---

### Adapter Behaviour

**File**: `lib/snakebridge/adapter.ex`

```elixir
defmodule SnakeBridge.Adapter do
  @moduledoc """
  Behaviour for SnakeBridge catalog adapters.

  Adapters provide library-specific integrations with optimizations
  and helpers beyond the generic adapter.
  """

  @type adapter_config :: %{
          python_module: String.t(),
          python_class: String.t(),
          name: atom(),
          description: String.t(),
          requires_packages: [String.t()],
          requires_env: [String.t()],
          supports_streaming: boolean()
        }

  @callback adapter_config() :: adapter_config()
  @callback setup_instructions() :: String.t()
end
```

---

### HexDocs Guide

**File**: `guides/adapters/00_adapter_catalog.md`

```markdown
# SnakeBridge Adapter Catalog

SnakeBridge ships with specialized adapters for common Python libraries.

## Generic Adapter (Default)

Works with ANY Python library via dynamic introspection.

**Use when**: Integrating any Python library
**Install**: Nothing extra needed
**Example**: json, numpy, requests, pandas

## GenAI Adapter

Optimized for Google Gemini with streaming support.

**Use when**: Building LLM applications with streaming responses
**Install**: `pip install google-genai`
**Requires**: `GEMINI_API_KEY` environment variable
**Example**: See `examples/genai_streaming.exs`

### Features
- Streaming text generation (token-by-token)
- Model shortcuts (gemini-flash-lite-latest)
- API key validation
- Error handling

### Quick Start
```elixir
SnakeBridge.use_adapter(:genai)
{:ok, stream} = GenAI.generate_stream(...)
```

See [GenAI Adapter Guide](01_genai.md) for details.

## Future Adapters

- **Requests** - HTTP with download progress
- **Pandas** - DataFrame chunking
- **TensorFlow** - Model inference
```

---

### mix.exs Updates

```elixir
# In mix.exs
def project do
  [
    # ...
    package: package(),
    docs: docs()
  ]
end

defp package do
  [
    files: ~w(
      lib
      priv/python/snakebridge_adapter
      priv/python/adapters/genai
      priv/python/setup.py
      .formatter.exs
      mix.exs
      README.md
      LICENSE
      CHANGELOG.md
    ),
    # ...
  ]
end

defp docs do
  [
    # ...
    extras: [
      "README.md",
      "CHANGELOG.md",
      "guides/adapters/00_adapter_catalog.md",
      "guides/adapters/01_genai.md"
    ],
    groups_for_extras: [
      "Guides": ["README.md"],
      "Adapters": ~r/guides\/adapters\/.*/,
      "Release Notes": ["CHANGELOG.md"]
    ],
    groups_for_modules: [
      "Core": [SnakeBridge, SnakeBridge.Config, ...],
      "Adapters": [
        SnakeBridge.Adapter,
        SnakeBridge.Adapters.Catalog,
        SnakeBridge.Adapters.GenAI
      ],
      # ...
    ]
  ]
end
```

---

## File Structure Summary

```
SnakeBridge Package (ships to users via Hex)
│
├── Generic Adapter (always available)
│   priv/python/snakebridge_adapter/
│
├── Catalog Adapters (opt-in, shipped with package)
│   priv/python/adapters/
│   ├── genai/
│   │   ├── adapter.py        ← GenAI adapter code
│   │   ├── __init__.py
│   │   └── README.md
│   └── (future adapters...)
│
├── Elixir Adapter Modules (in package)
│   lib/snakebridge/
│   ├── adapter.ex            ← Behaviour
│   └── adapters/
│       ├── catalog.ex        ← Registry
│       └── genai.ex          ← GenAI config
│
├── HexDocs Guides (published to hexdocs.pm)
│   guides/adapters/
│   ├── 00_adapter_catalog.md
│   └── 01_genai.md
│
└── Examples (in repo, not in hex package)
    examples/
    └── genai_streaming.exs   ← Uses the genai adapter
```

---

## User Experience

### Discovery

```bash
# User installs SnakeBridge
mix hex.info snakebridge

# Sees in docs: "Includes GenAI adapter for streaming"
```

### Usage

```elixir
# In their project
# 1. Check available adapters
SnakeBridge.Adapters.Catalog.list()
# => [%{name: :genai, description: "Google GenAI with streaming"}]

# 2. Get setup instructions
{:ok, config} = SnakeBridge.Adapters.Catalog.adapter_config(:genai)
IO.puts(SnakeBridge.Adapters.GenAI.setup_instructions())
# => "1. Install: pip install google-genai
#     2. Set API key: export GEMINI_API_KEY=..."

# 3. Use the adapter
SnakeBridge.use_adapter(:genai)

# 4. Integrate
{:ok, modules} = SnakeBridge.integrate("genai")
```

---

## Implementation Plan

### Phase 1: Catalog Infrastructure

1. Create `lib/snakebridge/adapter.ex` (behaviour)
2. Create `lib/snakebridge/adapters/catalog.ex` (registry)
3. Update `lib/snakebridge.ex` with `use_adapter/1`
4. Add to mix.exs docs configuration

### Phase 2: GenAI Adapter

1. Create `priv/python/adapters/genai/adapter.py`
2. Create `lib/snakebridge/adapters/genai.ex`
3. Write Python tests
4. Write Elixir integration test

### Phase 3: Documentation

1. Create `guides/adapters/00_adapter_catalog.md`
2. Create `guides/adapters/01_genai.md`
3. Update main README with adapter catalog section

### Phase 4: Example

1. Create `examples/genai_streaming.exs`
2. Demonstrate: basic generation + streaming

---

## Benefits

### For Users

✅ **Discover** adapters via `Catalog.list()`
✅ **Learn** via HexDocs guides
✅ **Install** via clear instructions
✅ **Use** via `SnakeBridge.use_adapter(:name)`

### For Maintainers

✅ **Organized** - Each adapter self-contained
✅ **Documented** - Guide per adapter
✅ **Tested** - Python + Elixir tests
✅ **Versioned** - Ships with SnakeBridge release

### For Ecosystem

✅ **Extensible** - Community can contribute adapters
✅ **Reusable** - One adapter, many users
✅ **Discoverable** - Listed in catalog
✅ **Quality** - Reviewed and tested

---

## GenAI Adapter Specifics

### Features

**Basic**:
- `generate_text(model, prompt)` - Simple request/response
- API key validation
- Error handling

**Streaming**:
- `generate_text_stream(model, prompt)` - Token-by-token
- Progress callbacks
- Cancellation support

### Models Supported

```elixir
# In adapter config
@models %{
  flash_lite: "gemini-flash-lite-latest",
  flash: "gemini-2.0-flash-exp",
  pro: "gemini-2.0-pro"
}
```

### Configuration

```elixir
# In user's config.exs
config :snakebridge,
  adapter: :genai,
  genai: %{
    default_model: "gemini-flash-lite-latest",
    timeout: 30_000,
    streaming: true
  }
```

---

## Implementation Details

### Adapter Selection in SnakeBridge

```elixir
# lib/snakebridge.ex

def use_adapter(adapter_name) when is_atom(adapter_name) do
  case SnakeBridge.Adapters.Catalog.adapter_config(adapter_name) do
    {:ok, config} ->
      # Configure Snakepit to use this adapter
      Application.put_env(:snakepit, :pools, [
        %{
          adapter_args: ["--adapter", config.python_module <> "." <> config.python_class]
        }
      ])
      {:ok, config}

    {:error, :adapter_not_found} ->
      {:error, "Adapter #{adapter_name} not found. Available: #{inspect(Catalog.list())}"}
  end
end
```

### Streaming in Generator

```elixir
# When generating from streaming function
def generate_function_module(descriptor, config) do
  # Check if function supports streaming
  streaming? = get_in(descriptor, [:supports_streaming]) || false

  if streaming? do
    # Generate with Stream/Flow handling
    quote do
      def function_name_stream(args, opts \\ []) do
        # Return Elixir Stream that wraps Python chunks
        Stream.resource(
          fn -> start_stream(args, opts) end,
          fn state -> fetch_chunk(state) end,
          fn state -> cleanup_stream(state) end
        )
      end
    end
  else
    # Regular function generation
  end
end
```

---

## Testing Strategy

### Python Tests

**File**: `priv/python/adapters/genai/test_adapter.py`

```python
class TestGenAIAdapter(unittest.TestCase):
    def test_requires_api_key(self):
        """Should fail without API key"""

    def test_basic_generation(self):
        """Should generate text"""

    def test_streaming_generation(self):
        """Should stream chunks"""
```

### Elixir Tests

**File**: `test/adapters/genai_test.exs`

```elixir
defmodule SnakeBridge.Adapters.GenAITest do
  use ExUnit.Case

  @moduletag :adapter
  @moduletag :genai

  test "catalog includes genai adapter" do
    adapters = SnakeBridge.Adapters.Catalog.list()
    assert Enum.any?(adapters, &(&1.name == :genai))
  end

  test "genai adapter has correct config" do
    {:ok, config} = SnakeBridge.Adapters.Catalog.adapter_config(:genai)
    assert config.name == :genai
    assert config.supports_streaming == true
  end

  @tag :live
  @tag :api_key_required
  test "can generate text with genai adapter" do
    # Requires GEMINI_API_KEY
    SnakeBridge.use_adapter(:genai)
    # Test actual generation...
  end
end
```

---

## Documentation in HexDocs

### Adapter Catalog Page

Shows up in hexdocs.pm/snakebridge as separate section:

**Sidebar**:
```
Guides
  Getting Started
  Architecture

Adapters ← NEW SECTION
  Adapter Catalog
  GenAI Adapter
  (Future adapters...)

API Reference
  Core
  Adapters
    SnakeBridge.Adapter
    SnakeBridge.Adapters.Catalog
    SnakeBridge.Adapters.GenAI
```

---

## Benefits of This Design

### Shipped with Package ✅
- Users get adapters when they install SnakeBridge
- No separate packages to manage
- Versioned together

### Documented ✅
- Guides in HexDocs
- README per adapter
- Module docs
- Examples

### Reusable ✅
- Import in any project
- Configure via catalog
- Standard interface

### Extensible ✅
- Add new adapters easily
- Follow established pattern
- Community can contribute (future: hex package plugins?)

---

## Next Steps

1. **Create behavior and catalog** (infrastructure)
2. **Build GenAI adapter** (first catalog adapter)
3. **Write guides** (documentation)
4. **Create example** (demonstrates usage)
5. **Test** (Python + Elixir)
6. **Publish** (v0.2.2 or v0.3.0)

---

## Summary

**Adapters are**:
- ✅ Part of SnakeBridge package (not separate)
- ✅ Documented in HexDocs
- ✅ Reusable by all users
- ✅ Cataloged and discoverable

**Examples are**:
- ✅ Demo code showing adapter usage
- ✅ In repo (examples/), not in hex package
- ✅ Reference implementation

**This gives users**:
- Immediate access to optimized integrations
- Clear documentation
- Working examples
- Extensible system

Ready to build?
