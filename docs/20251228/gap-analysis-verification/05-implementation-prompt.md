# Implementation Agent Prompt: SnakeBridge v0.7.0

You are implementing all P0 and P1 fixes identified in the SnakeBridge gap analysis verification. This is a comprehensive implementation task requiring TDD, full test coverage, and documentation updates.

---

## PHASE 0: REQUIRED READING

Before making ANY changes, you MUST read and understand these files completely.

### Documentation to Read First

```
docs/20251228/gap-analysis-verification/00-summary.md
docs/20251228/gap-analysis-verification/01-verified-gaps.md
docs/20251228/gap-analysis-verification/02-verified-implementations.md
docs/20251228/gap-analysis-verification/03-partial-findings.md
docs/20251228/gap-analysis-verification/04-recommendations.md
```

### Source Files to Read (in order)

```
# Core generator (PRIMARY CHANGES HERE)
lib/snakebridge/generator.ex
lib/snakebridge/generator/type_mapper.ex

# Compile task (strict mode changes)
lib/mix/tasks/compile/snakebridge.ex

# Supporting modules (understand contracts)
lib/snakebridge/runtime.ex
lib/snakebridge/config.ex
lib/snakebridge/manifest.ex
lib/snakebridge/lock.ex
lib/snakebridge/introspector.ex

# Docs pipeline (wire these in)
lib/snakebridge/docs.ex
lib/snakebridge/docs/rst_parser.ex
lib/snakebridge/docs/markdown_converter.ex
lib/snakebridge/docs/math_renderer.ex

# Telemetry (emit these)
lib/snakebridge/telemetry.ex
```

### Test Files to Read

```
test/snakebridge/generator_test.exs
test/snakebridge/introspector_test.exs
test/snakebridge/manifest_test.exs
test/snakebridge/runtime_test.exs
test/mix/tasks/compile/snakebridge_test.exs
```

### Existing Examples to Study

```
examples/
README.md
```

---

## PHASE 1: TEST-DRIVEN DEVELOPMENT SETUP

Create test files BEFORE implementation. All tests should FAIL initially.

### 1.1 Create `test/snakebridge/generator/wrapper_args_test.exs`

```elixir
defmodule SnakeBridge.Generator.WrapperArgsTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "build_params/1 with POSITIONAL_OR_KEYWORD defaults" do
    test "function with defaulted POSITIONAL_OR_KEYWORD params enables opts" do
      # Python: def mean(a, axis=None, dtype=None)
      params = [
        %{"name" => "a", "kind" => "POSITIONAL_OR_KEYWORD"},
        %{"name" => "axis", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "None"},
        %{"name" => "dtype", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "None"}
      ]

      {param_names, has_opts} = Generator.build_params(params)

      assert param_names == ["a"]
      assert has_opts == true, "opts should be enabled for defaulted params"
    end

    test "function with VAR_POSITIONAL enables opts" do
      # Python: def print(*values, sep=' ')
      params = [
        %{"name" => "values", "kind" => "VAR_POSITIONAL"},
        %{"name" => "sep", "kind" => "KEYWORD_ONLY", "default" => "' '"}
      ]

      {param_names, has_opts} = Generator.build_params(params)

      assert param_names == []
      assert has_opts == true
    end

    test "pure positional function still accepts opts for runtime flags" do
      # Python: def abs(x)
      # Even with no optional Python params, we need opts for idempotent/__runtime__
      params = [
        %{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"}
      ]

      {param_names, has_opts} = Generator.build_params(params)

      assert param_names == ["x"]
      # DESIGN DECISION: If Option A chosen, this should be true
      # If Option B chosen, this should be false
      assert has_opts == true, "runtime flags require opts access"
    end
  end

  describe "render_function/2 generates correct wrappers" do
    test "wrapper with defaulted params accepts keyword opts" do
      info = %{
        "name" => "mean",
        "parameters" => [
          %{"name" => "a", "kind" => "POSITIONAL_OR_KEYWORD"},
          %{"name" => "axis", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "None"}
        ],
        "docstring" => "Compute the arithmetic mean."
      }

      library = %SnakeBridge.Config.Library{
        name: :numpy,
        python_name: "numpy",
        module_name: Numpy,
        streaming: []
      }

      source = Generator.render_function(info, library)

      assert source =~ "def mean(a, opts \\\\ [])"
      assert source =~ "SnakeBridge.Runtime.call(__MODULE__, :mean, [a], opts)"
    end
  end
end
```

### 1.2 Create `test/snakebridge/generator/class_constructor_test.exs`

```elixir
defmodule SnakeBridge.Generator.ClassConstructorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "render_class/2 generates correct constructors" do
    test "class with no __init__ args generates new/0 or new/1 with opts" do
      class_info = %{
        "name" => "Empty",
        "python_module" => "mylib",
        "methods" => [
          %{"name" => "__init__", "parameters" => []}
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :mylib,
        python_name: "mylib",
        module_name: Mylib
      }

      source = Generator.render_class(class_info, library)

      # Should generate new() or new(opts \\ []) depending on design decision
      assert source =~ "def new("
      refute source =~ "def new(arg, opts"
    end

    test "class with multiple required __init__ args generates correct new/N" do
      class_info = %{
        "name" => "Point",
        "python_module" => "geometry",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "y", "kind" => "POSITIONAL_OR_KEYWORD"}
            ]
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :geometry,
        python_name: "geometry",
        module_name: Geometry
      }

      source = Generator.render_class(class_info, library)

      assert source =~ "def new(x, y"
      assert source =~ "call_class(__MODULE__, :__init__, [x, y]"
    end

    test "class with optional __init__ args generates new with opts" do
      class_info = %{
        "name" => "Config",
        "python_module" => "mylib",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [
              %{"name" => "path", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "readonly", "kind" => "POSITIONAL_OR_KEYWORD", "default" => "False"}
            ]
          }
        ],
        "attributes" => []
      }

      library = %SnakeBridge.Config.Library{
        name: :mylib,
        python_name: "mylib",
        module_name: Mylib
      }

      source = Generator.render_class(class_info, library)

      assert source =~ "def new(path, opts \\\\ [])"
      assert source =~ "call_class(__MODULE__, :__init__, [path], opts)"
    end
  end
end
```

### 1.3 Create `test/snakebridge/generator/streaming_test.exs`

```elixir
defmodule SnakeBridge.Generator.StreamingTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "render_function/2 with streaming" do
    test "streaming function generates both normal and stream variants" do
      info = %{
        "name" => "generate",
        "parameters" => [
          %{"name" => "prompt", "kind" => "POSITIONAL_OR_KEYWORD"}
        ],
        "docstring" => "Generate text from prompt."
      }

      library = %SnakeBridge.Config.Library{
        name: :llm,
        python_name: "llm",
        module_name: Llm,
        streaming: ["generate"]  # This function is streaming
      }

      source = Generator.render_function(info, library)

      # Normal variant
      assert source =~ "def generate(prompt"

      # Streaming variant
      assert source =~ "def generate_stream("
      assert source =~ "when is_function(callback, 1)"
      assert source =~ "SnakeBridge.Runtime.stream("

      # Streaming variant has @spec
      assert source =~ "@spec generate_stream("
      assert source =~ ":: :ok | {:error, Snakepit.Error.t()}"
    end

    test "streaming variant always accepts opts for runtime flags" do
      info = %{
        "name" => "stream_data",
        "parameters" => [
          %{"name" => "source", "kind" => "POSITIONAL_OR_KEYWORD"}
        ],
        "docstring" => "Stream data."
      }

      library = %SnakeBridge.Config.Library{
        name: :data,
        python_name: "data",
        module_name: Data,
        streaming: ["stream_data"]
      }

      source = Generator.render_function(info, library)

      # Streaming variant must accept opts even if Python has no optional params
      assert source =~ "def stream_data_stream(source, opts \\\\ [], callback)"
    end

    test "non-streaming function does not generate stream variant" do
      info = %{
        "name" => "compute",
        "parameters" => [%{"name" => "x", "kind" => "POSITIONAL_OR_KEYWORD"}],
        "docstring" => "Compute."
      }

      library = %SnakeBridge.Config.Library{
        name: :math,
        python_name: "math",
        module_name: Math,
        streaming: []  # No streaming functions
      }

      source = Generator.render_function(info, library)

      assert source =~ "def compute(x"
      refute source =~ "def compute_stream("
    end
  end
end
```

### 1.4 Create `test/snakebridge/generator/write_if_changed_test.exs`

```elixir
defmodule SnakeBridge.Generator.WriteIfChangedTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  @tag :tmp_dir
  describe "write_if_changed/2" do
    test "writes file when content is new", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "new_file.ex")
      content = "defmodule New do\nend"

      result = Generator.write_if_changed(path, content)

      assert result == :written
      assert File.read!(path) == content
    end

    test "skips write when content is identical", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "existing.ex")
      content = "defmodule Existing do\nend"

      # Write initial content
      File.write!(path, content)
      initial_stat = File.stat!(path)

      # Small delay to ensure mtime would change if rewritten
      Process.sleep(10)

      result = Generator.write_if_changed(path, content)

      assert result == :unchanged
      # Content should be identical
      assert File.read!(path) == content
    end

    test "rewrites file when content differs", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "changed.ex")
      old_content = "defmodule Old do\nend"
      new_content = "defmodule New do\nend"

      File.write!(path, old_content)

      result = Generator.write_if_changed(path, new_content)

      assert result == :written
      assert File.read!(path) == new_content
    end

    test "no temp files left behind after write", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "clean.ex")
      content = "defmodule Clean do\nend"

      Generator.write_if_changed(path, content)

      # No .tmp files should exist
      tmp_files = Path.wildcard(Path.join(tmp_dir, "*.tmp*"))
      assert tmp_files == []
    end

    test "concurrent writes don't corrupt file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "concurrent.ex")

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            content = "defmodule Concurrent#{i} do\nend"
            Generator.write_if_changed(path, content)
          end)
        end

      Task.await_many(tasks)

      # File should exist and be valid Elixir
      content = File.read!(path)
      assert content =~ "defmodule Concurrent"
      assert {:ok, _} = Code.string_to_quoted(content)
    end
  end
end
```

### 1.5 Create `test/mix/tasks/compile/snakebridge_strict_test.exs`

```elixir
defmodule Mix.Tasks.Compile.SnakebridgeStrictTest do
  use ExUnit.Case

  alias Mix.Tasks.Compile.Snakebridge

  @tag :tmp_dir
  describe "strict mode verification" do
    test "fails when generated file is missing", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      # Create manifest but NOT the generated file
      File.mkdir_p!(config.metadata_dir)
      manifest = %{"version" => "0.7.0", "symbols" => %{}, "classes" => %{}}
      File.write!(Path.join(config.metadata_dir, "manifest.json"), Jason.encode!(manifest))

      assert_raise SnakeBridge.CompileError, ~r/Generated file missing/, fn ->
        Snakebridge.verify_generated_files_exist!(config)
      end
    end

    test "fails when expected function missing from generated file", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      # Create generated file WITHOUT the expected function
      File.mkdir_p!(config.generated_dir)
      File.write!(
        Path.join(config.generated_dir, "testlib.ex"),
        "defmodule Testlib do\nend"
      )

      # Create manifest WITH the function
      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{
          "Testlib.compute/1" => %{
            "name" => "compute",
            "python_module" => "testlib",
            "module" => "Testlib"
          }
        },
        "classes" => %{}
      }
      File.mkdir_p!(config.metadata_dir)
      File.write!(Path.join(config.metadata_dir, "manifest.json"), Jason.encode!(manifest))

      assert_raise SnakeBridge.CompileError, ~r/missing expected functions/, fn ->
        Snakebridge.verify_symbols_present!(config, manifest)
      end
    end

    test "passes when all symbols present in generated file", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      # Create generated file WITH the expected function
      File.mkdir_p!(config.generated_dir)
      File.write!(
        Path.join(config.generated_dir, "testlib.ex"),
        """
        defmodule Testlib do
          def compute(x, opts \\\\ []) do
            SnakeBridge.Runtime.call(__MODULE__, :compute, [x], opts)
          end
        end
        """
      )

      # Create manifest WITH the function
      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{
          "Testlib.compute/1" => %{
            "name" => "compute",
            "python_module" => "testlib",
            "module" => "Testlib"
          }
        },
        "classes" => %{}
      }
      File.mkdir_p!(config.metadata_dir)
      File.write!(Path.join(config.metadata_dir, "manifest.json"), Jason.encode!(manifest))

      # Should not raise
      assert :ok == Snakebridge.verify_generated_files_exist!(config)
      assert :ok == Snakebridge.verify_symbols_present!(config, manifest)
    end
  end
end
```

### 1.6 Create `test/snakebridge/generator/docstring_test.exs`

```elixir
defmodule SnakeBridge.Generator.DocstringTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "format_docstring/1" do
    test "converts NumPy-style docstring to ExDoc markdown" do
      raw = """
      Compute the arithmetic mean along the specified axis.

      Parameters
      ----------
      a : array_like
          Array containing numbers whose mean is desired.
      axis : None or int or tuple of ints, optional
          Axis or axes along which the means are computed.

      Returns
      -------
      m : ndarray
          The mean of the input array.
      """

      formatted = Generator.format_docstring(raw)

      # Should have markdown headers
      assert formatted =~ "## Parameters"
      assert formatted =~ "## Returns"
      # Should convert params to list format
      assert formatted =~ "- `a`"
      assert formatted =~ "- `axis`"
    end

    test "handles nil docstring gracefully" do
      assert Generator.format_docstring(nil) == ""
    end

    test "handles empty docstring gracefully" do
      assert Generator.format_docstring("") == ""
    end

    test "falls back to raw doc on parse failure" do
      raw = "Some unparseable <<< garbage >>> docstring"

      formatted = Generator.format_docstring(raw)

      # Should return something (either parsed or raw fallback)
      assert is_binary(formatted)
    end

    test "renders math expressions" do
      raw = "The formula is :math:`E = mc^2`."

      formatted = Generator.format_docstring(raw)

      # Should convert RST math to KaTeX format
      assert formatted =~ "$E = mc^2$"
    end
  end
end
```

### 1.7 Create `test/snakebridge/telemetry_emission_test.exs`

```elixir
defmodule SnakeBridge.TelemetryEmissionTest do
  use ExUnit.Case

  describe "compile pipeline telemetry" do
    setup do
      test_pid = self()

      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:snakebridge, :compile, :start],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.attach(
        "#{handler_id}-stop",
        [:snakebridge, :compile, :stop],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        :telemetry.detach("#{handler_id}-stop")
      end)

      :ok
    end

    @tag :integration
    test "compile emits start and stop events" do
      # This test requires a real compile run
      # Skip if not in integration test mode
      # The implementation should emit:
      # - [:snakebridge, :compile, :start] at beginning
      # - [:snakebridge, :compile, :stop] at end

      # Placeholder for integration test
      assert true
    end
  end
end
```

---

## PHASE 2: IMPLEMENTATION

Implement changes in this order. After each change, run tests to verify.

### 2.1 Implement `build_params/1` Fix

**File:** `lib/snakebridge/generator.ex`

**Design Decision:** Implement Option A (all wrappers accept opts unconditionally)

```elixir
# Replace existing build_params/1
defp build_params(params) do
  required =
    params
    |> Enum.filter(&(&1["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]))
    |> Enum.reject(&Map.has_key?(&1, "default"))

  param_names = Enum.map(required, &sanitize_name/1)

  # DESIGN: Always enable opts for runtime flag access (idempotent, __runtime__, __args__)
  # This is the canonical FFI posture - consistent and predictable
  {param_names, true}
end
```

**Run tests:** `mix test test/snakebridge/generator/wrapper_args_test.exs`

### 2.2 Implement `render_class/2` and `render_constructor/2`

**File:** `lib/snakebridge/generator.ex`

See `04-recommendations.md` Fix #2 for full implementation.

Key changes:
- Extract `__init__` parameters from `class_info["methods"]`
- Call `build_params/1` on init params
- Generate `new/N` with correct arity

**Run tests:** `mix test test/snakebridge/generator/class_constructor_test.exs`

### 2.3 Implement Streaming Generation

**File:** `lib/snakebridge/generator.ex`

See `04-recommendations.md` Fix #3 for full implementation.

Key changes:
- Change `render_function/1` to `render_function/2` (add library param)
- Add `render_normal_function/5`
- Add `render_streaming_variant/4`
- Update `render_library/4` to pass library
- Update `render_submodule/2` to `render_submodule/3`

**Run tests:** `mix test test/snakebridge/generator/streaming_test.exs`

### 2.4 Implement `write_if_changed/2`

**File:** `lib/snakebridge/generator.ex`

See `04-recommendations.md` Fix #4 for full implementation.

Key points:
- Use `System.unique_integer([:positive])` for temp file
- Clean up temp file in `after` block
- Preserve `:ok` return from `generate_library/4`

**Run tests:** `mix test test/snakebridge/generator/write_if_changed_test.exs`

### 2.5 Implement Strict Mode Verification

**File:** `lib/mix/tasks/compile/snakebridge.ex`

See `04-recommendations.md` Fix #5 for full implementation.

Add:
- `verify_generated_files_exist!/1`
- `verify_symbols_present!/2`

**Run tests:** `mix test test/mix/tasks/compile/snakebridge_strict_test.exs`

### 2.6 Wire Documentation Pipeline

**File:** `lib/snakebridge/generator.ex`

```elixir
defp format_docstring(nil), do: ""
defp format_docstring(""), do: ""

defp format_docstring(raw_doc) do
  raw_doc
  |> SnakeBridge.Docs.RstParser.parse()
  |> SnakeBridge.Docs.MarkdownConverter.convert()
rescue
  _ -> raw_doc
end
```

Update `render_normal_function/5` to use `format_docstring/1`.

**Run tests:** `mix test test/snakebridge/generator/docstring_test.exs`

### 2.7 Add Telemetry Emission

**File:** `lib/mix/tasks/compile/snakebridge.ex`

Wrap `run_normal/1`:

```elixir
defp run_normal(config) do
  start_time = System.monotonic_time()
  libraries = Enum.map(config.libraries, & &1.name)
  SnakeBridge.Telemetry.compile_start(libraries, false)

  try do
    # ... existing implementation ...

    symbol_count = count_symbols(updated_manifest)
    file_count = length(config.libraries)
    SnakeBridge.Telemetry.compile_stop(start_time, symbol_count, file_count, libraries, :normal)
    {:ok, []}
  rescue
    e ->
      SnakeBridge.Telemetry.compile_exception(start_time, e, __STACKTRACE__)
      reraise e, __STACKTRACE__
  end
end

defp count_symbols(manifest) do
  symbols = Map.get(manifest, "symbols", %{}) |> map_size()
  classes = Map.get(manifest, "classes", %{}) |> map_size()
  symbols + classes
end
```

---

## PHASE 3: EXAMPLES

Create example files demonstrating new functionality.

### 3.1 Create `examples/wrapper_args_example.exs`

```elixir
# examples/wrapper_args_example.exs
#
# Demonstrates that generated wrappers properly handle optional arguments
# and runtime flags.
#
# Run with: elixir examples/wrapper_args_example.exs

Mix.install([
  {:snakebridge, path: "."},
  {:snakepit, "~> 0.8.1"}
])

# Assuming numpy bindings are generated
defmodule WrapperArgsDemo do
  @moduledoc """
  Demonstrates wrapper argument handling for Python functions with optional params.
  """

  def run do
    IO.puts("=== Wrapper Arguments Demo ===\n")

    # Example 1: Function with optional Python kwargs
    IO.puts("1. Calling numpy.mean with axis option:")
    case Numpy.mean([1, 2, 3, 4], axis: 0) do
      {:ok, result} -> IO.puts("   Result: #{inspect(result)}")
      {:error, e} -> IO.puts("   Error: #{inspect(e)}")
    end

    # Example 2: Using runtime flags
    IO.puts("\n2. Using idempotent flag for caching:")
    case Numpy.mean([1, 2, 3], idempotent: true) do
      {:ok, result} -> IO.puts("   Result: #{inspect(result)}")
      {:error, e} -> IO.puts("   Error: #{inspect(e)}")
    end

    # Example 3: Using __args__ for varargs
    IO.puts("\n3. Using __args__ for variadic functions:")
    # For functions like print(*values)
    case SomeLib.variadic_func([], __args__: [1, 2, 3]) do
      {:ok, result} -> IO.puts("   Result: #{inspect(result)}")
      {:error, e} -> IO.puts("   Error: #{inspect(e)}")
    end

    IO.puts("\n=== Demo Complete ===")
  end
end

WrapperArgsDemo.run()
```

### 3.2 Create `examples/class_constructor_example.exs`

```elixir
# examples/class_constructor_example.exs
#
# Demonstrates that class constructors match Python __init__ signatures.
#
# Run with: elixir examples/class_constructor_example.exs

Mix.install([
  {:snakebridge, path: "."},
  {:snakepit, "~> 0.8.1"}
])

defmodule ClassConstructorDemo do
  @moduledoc """
  Demonstrates class constructor generation matching Python __init__ signatures.
  """

  def run do
    IO.puts("=== Class Constructor Demo ===\n")

    # Example 1: Class with no __init__ args
    IO.puts("1. Creating instance with no args:")
    case SomeLib.EmptyClass.new() do
      {:ok, ref} -> IO.puts("   Created: #{inspect(ref)}")
      {:error, e} -> IO.puts("   Error: #{inspect(e)}")
    end

    # Example 2: Class with multiple required args
    IO.puts("\n2. Creating Point(x, y):")
    case Geometry.Point.new(10, 20) do
      {:ok, ref} ->
        IO.puts("   Created: #{inspect(ref)}")
        {:ok, x} = Geometry.Point.x(ref)
        {:ok, y} = Geometry.Point.y(ref)
        IO.puts("   Coordinates: (#{x}, #{y})")
      {:error, e} ->
        IO.puts("   Error: #{inspect(e)}")
    end

    # Example 3: Class with optional __init__ args
    IO.puts("\n3. Creating Config with optional readonly:")
    case MyLib.Config.new("/path/to/file", readonly: true) do
      {:ok, ref} -> IO.puts("   Created: #{inspect(ref)}")
      {:error, e} -> IO.puts("   Error: #{inspect(e)}")
    end

    IO.puts("\n=== Demo Complete ===")
  end
end

ClassConstructorDemo.run()
```

### 3.3 Create `examples/streaming_example.exs`

```elixir
# examples/streaming_example.exs
#
# Demonstrates streaming function variants.
#
# Run with: elixir examples/streaming_example.exs

Mix.install([
  {:snakebridge, path: "."},
  {:snakepit, "~> 0.8.1"}
])

defmodule StreamingDemo do
  @moduledoc """
  Demonstrates streaming function generation and usage.
  """

  def run do
    IO.puts("=== Streaming Demo ===\n")

    # Example 1: Normal (non-streaming) call
    IO.puts("1. Normal call (returns complete result):")
    case LLM.generate("Hello") do
      {:ok, result} -> IO.puts("   Result: #{inspect(result)}")
      {:error, e} -> IO.puts("   Error: #{inspect(e)}")
    end

    # Example 2: Streaming call with callback
    IO.puts("\n2. Streaming call (receives chunks):")
    callback = fn chunk ->
      IO.write("   Chunk: #{inspect(chunk)}\n")
    end

    case LLM.generate_stream("Hello", [], callback) do
      :ok -> IO.puts("   Stream complete")
      {:error, e} -> IO.puts("   Error: #{inspect(e)}")
    end

    # Example 3: Streaming with runtime options
    IO.puts("\n3. Streaming with timeout option:")
    case LLM.generate_stream("Hello", [__runtime__: [timeout: 30_000]], callback) do
      :ok -> IO.puts("   Stream complete")
      {:error, e} -> IO.puts("   Error: #{inspect(e)}")
    end

    IO.puts("\n=== Demo Complete ===")
  end
end

StreamingDemo.run()
```

### 3.4 Create `examples/strict_mode_example.exs`

```elixir
# examples/strict_mode_example.exs
#
# Demonstrates strict mode for CI environments.
#
# Run with: SNAKEBRIDGE_STRICT=1 elixir examples/strict_mode_example.exs

Mix.install([
  {:snakebridge, path: "."},
  {:snakepit, "~> 0.8.1"}
])

defmodule StrictModeDemo do
  @moduledoc """
  Demonstrates strict mode verification for CI pipelines.

  In strict mode, SnakeBridge will:
  1. Verify all detected symbols are in the manifest
  2. Verify all generated files exist
  3. Verify expected functions are present in generated files

  This ensures the committed generated code is complete and consistent.
  """

  def run do
    IO.puts("=== Strict Mode Demo ===\n")

    strict? = System.get_env("SNAKEBRIDGE_STRICT") == "1"

    IO.puts("Strict mode: #{if strict?, do: "ENABLED", else: "disabled"}")
    IO.puts("")

    if strict? do
      IO.puts("""
      In strict mode, the compiler will fail if:
      - Any symbol used in your code is not in the manifest
      - Any generated .ex file is missing
      - Any expected function is not defined in the generated file

      This is ideal for CI where you want to catch:
      - Forgotten regeneration after Python library updates
      - Missing commits of generated files
      - Manifest/source drift
      """)
    else
      IO.puts("""
      To enable strict mode, set:
        SNAKEBRIDGE_STRICT=1

      Or in config:
        config :snakebridge, strict: true
      """)
    end

    IO.puts("=== Demo Complete ===")
  end
end

StrictModeDemo.run()
```

### 3.5 Update `examples/run_all.sh`

```bash
#!/bin/bash
# examples/run_all.sh
#
# Runs all SnakeBridge examples

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "========================================"
echo "Running SnakeBridge Examples"
echo "========================================"
echo ""

# Existing examples
for example in basic_usage complete_workflow telemetry_demo; do
  if [ -f "examples/${example}.exs" ]; then
    echo "--- Running ${example}.exs ---"
    elixir "examples/${example}.exs"
    echo ""
  fi
done

# New examples for v0.7.0
echo "--- Running wrapper_args_example.exs ---"
elixir examples/wrapper_args_example.exs
echo ""

echo "--- Running class_constructor_example.exs ---"
elixir examples/class_constructor_example.exs
echo ""

echo "--- Running streaming_example.exs ---"
elixir examples/streaming_example.exs
echo ""

echo "--- Running strict_mode_example.exs ---"
elixir examples/strict_mode_example.exs
echo ""

echo "========================================"
echo "All examples completed successfully!"
echo "========================================"
```

---

## PHASE 4: DOCUMENTATION UPDATES

### 4.1 Update `mix.exs`

```elixir
@version "0.7.0"
```

### 4.2 Update `CHANGELOG.md`

Add at the top:

```markdown
## [0.7.0] - 2025-12-28

### Added
- **Wrapper argument surface fix**: All generated wrappers now accept `opts \\ []` for runtime flags (`idempotent`, `__runtime__`, `__args__`) and Python kwargs
- **Streaming generation**: Functions in `streaming:` config now generate `*_stream` variants with proper `@spec`
- **Strict mode verification**: Now verifies generated files exist and contain expected functions
- **Documentation pipeline**: Docstrings are converted from RST/NumPy/Google style to ExDoc Markdown
- **Telemetry emission**: Compile pipeline now emits `[:snakebridge, :compile, :start|:stop|:exception]` events

### Changed
- Class constructors now match Python `__init__` signatures instead of hardcoded `new(arg, opts)`
- File writes use atomic temp files with unique names for concurrency safety
- File writes skip when content unchanged (no more mtime churn)

### Fixed
- Functions with `POSITIONAL_OR_KEYWORD` defaulted parameters now accept opts
- `VAR_POSITIONAL` parameters are now recognized for opts enablement
- Classes with 0, 2+, or optional `__init__` args now construct correctly

### Developer Experience
- New examples: `wrapper_args_example.exs`, `class_constructor_example.exs`, `streaming_example.exs`, `strict_mode_example.exs`
- Updated `run_all.sh` with new examples
```

### 4.3 Update `README.md`

Replace the README with an updated version that includes:

```markdown
# SnakeBridge

[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snakebridge)

Compile-time generator for type-safe Elixir bindings to Python libraries.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:snakebridge, "~> 0.7.0",
      libraries: [
        {:numpy, "1.26.0"},
        {:pandas, version: "2.0.0", include: ["DataFrame", "read_csv"]}
      ]}
  ]
end
```

## Quick Start

```elixir
# Generated wrappers work like native Elixir
{:ok, result} = Numpy.mean([1, 2, 3, 4])

# Optional Python arguments via keyword opts
{:ok, result} = Numpy.mean([[1, 2], [3, 4]], axis: 0)

# Runtime flags (idempotent caching, timeouts)
{:ok, result} = Numpy.mean([1, 2, 3], idempotent: true)
```

## Features

### Generated Wrappers

SnakeBridge generates Elixir modules that wrap Python libraries:

```elixir
# Python: numpy.mean(a, axis=None, dtype=None, keepdims=False)
# Generated: Numpy.mean(a, opts \\ [])

Numpy.mean([1, 2, 3])                    # Basic call
Numpy.mean([1, 2, 3], axis: 0)           # With Python kwargs
Numpy.mean([1, 2, 3], idempotent: true)  # With runtime flags
```

All wrappers accept `opts` for:
- **Python kwargs**: Passed to the Python function
- **Runtime flags**: `idempotent`, `__runtime__`, `__args__`

### Class Constructors

Classes generate `new/N` matching their Python `__init__`:

```elixir
# Python: class Point:
#           def __init__(self, x, y): ...
# Generated: Geometry.Point.new(x, y, opts \\ [])

{:ok, point} = Geometry.Point.new(10, 20)
{:ok, x} = Geometry.Point.x(point)  # Attribute access
```

### Streaming Functions

Configure streaming functions to generate `*_stream` variants:

```elixir
# In mix.exs
{:llm, version: "1.0", streaming: ["generate", "complete"]}

# Generated variants:
LLM.generate(prompt)                              # Returns complete result
LLM.generate_stream(prompt, opts, callback)       # Streams chunks to callback

# Usage:
LLM.generate_stream("Hello", [], fn chunk ->
  IO.write(chunk)
end)
```

### Strict Mode for CI

Enable strict mode to verify generated code integrity:

```bash
# In CI
SNAKEBRIDGE_STRICT=1 mix compile
```

Strict mode verifies:
1. All used symbols are in the manifest
2. All generated files exist
3. Expected functions are present in generated files

### Documentation Conversion

Python docstrings are converted to ExDoc Markdown:

- NumPy style → Markdown sections
- Google style → Markdown sections
- RST math (`:math:\`E=mc^2\``) → KaTeX (`$E=mc^2$`)

### Telemetry

The compile pipeline emits telemetry events:

```elixir
# Attach handler
:telemetry.attach("my-handler", [:snakebridge, :compile, :stop], fn _, measurements, _, _ ->
  IO.puts("Compiled #{measurements.symbols_generated} symbols")
end, nil)
```

Events:
- `[:snakebridge, :compile, :start]`
- `[:snakebridge, :compile, :stop]`
- `[:snakebridge, :compile, :exception]`

## Configuration

```elixir
# mix.exs
{:snakebridge, "~> 0.7.0",
  libraries: [
    # Simple: name and version
    {:numpy, "1.26.0"},

    # Full options
    {:pandas,
      version: "2.0.0",
      pypi_package: "pandas",
      include: ["DataFrame", "read_csv", "read_json"],
      exclude: ["testing"],
      streaming: ["read_csv_chunked"],
      submodules: true}
  ],
  generated_dir: "lib/python_bindings",
  metadata_dir: ".snakebridge"
}

# config/config.exs
config :snakebridge,
  auto_install: :dev,      # :never | :dev | :always
  strict: false,           # or SNAKEBRIDGE_STRICT=1
  verbose: false
```

## Mix Tasks

```bash
mix snakebridge.setup          # Install Python packages
mix snakebridge.setup --check  # Verify packages installed
mix snakebridge.verify         # Verify hardware compatibility
mix snakebridge.verify --strict # Fail on any mismatch
```

## Examples

See the `examples/` directory:

```bash
# Run all examples
./examples/run_all.sh

# Individual examples
elixir examples/wrapper_args_example.exs
elixir examples/class_constructor_example.exs
elixir examples/streaming_example.exs
elixir examples/strict_mode_example.exs
```

## Architecture

SnakeBridge is a compile-time code generator:

1. **Scan**: Find calls to configured library modules in your code
2. **Introspect**: Query Python for function/class signatures
3. **Generate**: Create Elixir wrapper modules with proper arities
4. **Lock**: Record environment for reproducibility

Runtime calls delegate to [Snakepit](https://hex.pm/packages/snakepit).

## Requirements

- Elixir ~> 1.14
- Python 3.8+
- Snakepit ~> 0.8.1

## License

MIT
```

---

## PHASE 5: FINAL VERIFICATION

Run these commands and ensure ALL pass with no warnings:

```bash
# Clean build
mix clean
mix deps.get

# Compile with warnings as errors
mix compile --warnings-as-errors

# Run all tests
mix test

# Run specific test suites
mix test test/snakebridge/generator/
mix test test/mix/tasks/

# Dialyzer
mix dialyzer

# Credo
mix credo --strict

# Format check
mix format --check-formatted

# Docs generation
mix docs

# Run examples (if Python environment available)
./examples/run_all.sh
```

### Checklist Before Completion

- [ ] All tests pass
- [ ] No compiler warnings
- [ ] No dialyzer warnings
- [ ] No credo issues
- [ ] Code formatted
- [ ] CHANGELOG.md updated with 2025-12-28 date
- [ ] mix.exs version is 0.7.0
- [ ] README.md updated with new features
- [ ] README.md version references are 0.7.0
- [ ] All new examples run without error
- [ ] examples/run_all.sh includes new examples
- [ ] Documentation generates without errors

---

## IMPORTANT CONSTRAINTS

1. **TDD**: Write tests FIRST, see them FAIL, then implement
2. **No warnings**: `mix compile --warnings-as-errors` must pass
3. **No dialyzer errors**: `mix dialyzer` must pass
4. **Atomic changes**: Each fix should be a logical commit
5. **Backwards compatible**: Existing functionality must not break
6. **Design decision**: Use Option A (all wrappers accept opts) for consistency
