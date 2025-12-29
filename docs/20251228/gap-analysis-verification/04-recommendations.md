# Prioritized Fix Recommendations

Based on code verification, these are the recommended fixes in priority order.

---

## P0: Ship-Blocking Fixes

### 1. Fix Wrapper Argument Surface (HIGHEST PRIORITY)

**The Problem:**
`build_params/1` treats only `KEYWORD_ONLY`/`VAR_KEYWORD` as needing `opts`.

**Design Decision Required:**

The `opts` keyword list serves TWO purposes in the current runtime design:
1. **Python kwargs** - Passed to the Python function
2. **Runtime flags** - `idempotent`, `__runtime__` (pool/session/timeouts), `__args__` (varargs)

Even functions with only required positional parameters may need runtime flags. The current design conflates these.

**Options:**

**Option A: All wrappers accept `opts \\ []` unconditionally (Recommended for canonical FFI)**
- Simplest, most consistent
- Every generated wrapper accepts runtime flags
- No special cases to document

**Option B: Runtime flags available only via `SnakeBridge.Runtime.call/4` directly**
- Wrappers are "clean" but limited
- Users must know to bypass wrappers for runtime options
- Requires clear documentation

**The Fix (Option A):**

```elixir
# lib/snakebridge/generator.ex

defp build_params(params) do
  required =
    params
    |> Enum.filter(&(&1["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]))
    |> Enum.reject(&Map.has_key?(&1, "default"))

  param_names = Enum.map(required, &sanitize_name/1)

  # DECISION: Always enable opts for runtime flag access
  # Even pure-positional Python functions need idempotent/__runtime__ access
  {param_names, true}
end
```

**Alternative Fix (Option B - detect optional only):**

```elixir
defp build_params(params) do
  required =
    params
    |> Enum.filter(&(&1["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]))
    |> Enum.reject(&Map.has_key?(&1, "default"))

  # Check for ANY optional parameters OR varargs
  has_optional =
    Enum.any?(params, fn p ->
      p["kind"] in ["KEYWORD_ONLY", "VAR_KEYWORD", "VAR_POSITIONAL"] or
        Map.has_key?(p, "default")
    end)

  param_names = Enum.map(required, &sanitize_name/1)
  {param_names, has_optional}
end
```

**Files to Change:**
- `lib/snakebridge/generator.ex` - `build_params/1`

**Call-Sites to Verify:**
- `render_function/1` - uses `build_params/1`
- `render_method/1` - uses `build_params/1`
- `render_constructor/2` (new) - will use `build_params/1`

**Tests to Add:**
- Function with `POSITIONAL_OR_KEYWORD` defaulted params generates `opts`
- Function with `VAR_POSITIONAL` generates `opts`
- (If Option A) Pure positional function still accepts `opts`

---

### 2. Fix Class Constructors

**The Problem:**
All classes get `new(arg, opts \\ [])` regardless of actual `__init__` signature.

**The Fix:**

```elixir
# lib/snakebridge/generator.ex

defp render_class(class_info, library) do
  class_name = class_name(class_info)
  python_module = class_python_module(class_info, library)
  module_name = class_module_name(class_info, library)
  relative_module = relative_module_name(library, module_name)

  methods = class_info["methods"] || []
  attrs = class_info["attributes"] || []

  # Find __init__ method to get its parameters
  init_method = Enum.find(methods, fn m -> m["name"] == "__init__" end)
  init_params = (init_method && init_method["parameters"]) || []

  # Use build_params for constructor, same as functions
  {param_names, has_opts} = build_params(init_params)
  constructor = render_constructor(param_names, has_opts)

  methods_source =
    methods
    |> Enum.reject(fn m -> m["name"] == "__init__" end)
    |> Enum.map_join("\n\n", &render_method/1)

  attrs_source =
    attrs
    |> Enum.map_join("\n\n", &render_attribute/1)

  """
    defmodule #{relative_module} do
      def __snakebridge_python_name__, do: "#{python_module}"
      def __snakebridge_python_class__, do: "#{class_name}"

  #{constructor}

  #{indent(methods_source, 4)}

  #{indent(attrs_source, 4)}
    end
  """
end

defp render_constructor(param_names, has_opts) do
  args = "[" <> Enum.join(param_names, ", ") <> "]"

  param_list = if has_opts do
    Enum.join(param_names ++ ["opts \\\\ []"], ", ")
  else
    Enum.join(param_names, ", ")
  end

  call = if has_opts do
    "SnakeBridge.Runtime.call_class(__MODULE__, :__init__, #{args}, opts)"
  else
    "SnakeBridge.Runtime.call_class(__MODULE__, :__init__, #{args})"
  end

  spec_args = Enum.map(param_names, fn _ -> "term()" end)
  spec_args = if has_opts, do: spec_args ++ ["keyword()"], else: spec_args
  spec_args_str = Enum.join(spec_args, ", ")

  """
      @spec new(#{spec_args_str}) :: {:ok, Snakepit.PyRef.t()} | {:error, Snakepit.Error.t()}
      def new(#{param_list}) do
        #{call}
      end
  """
end
```

**Files to Change:**
- `lib/snakebridge/generator.ex` - `render_class/2`, add `render_constructor/2`

---

### 3. Implement Streaming Generation

**The Problem:**
Config has `streaming:` but generator ignores it.

**Known Limitations:**
1. **Name collision risk:** `library.streaming` is a list of function names. Same function name in different submodules will collide. Consider `python_module:function` format for disambiguation in future.
2. **Runtime opts:** When `has_opts` is false, streaming wrappers can't accept runtime flags.

**The Fix:**

```elixir
# lib/snakebridge/generator.ex

# Change render_function/1 to render_function/2, passing library
defp render_function(info, library) do
  name = info["name"]
  params = info["parameters"] || []
  doc = info["docstring"] || ""

  {param_names, has_opts} = build_params(params)
  args = "[" <> Enum.join(param_names, ", ") <> "]"

  # Check if this function should have streaming variant
  # NOTE: This matches by name only; same name in different submodules will collide
  is_streaming = name in (library.streaming || [])

  normal = render_normal_function(name, param_names, has_opts, args, doc)

  if is_streaming do
    streaming = render_streaming_variant(name, param_names, has_opts, args)
    normal <> "\n\n" <> streaming
  else
    normal
  end
end

defp render_normal_function(name, param_names, has_opts, args, doc) do
  call = runtime_call(name, args, has_opts)
  spec = function_spec(name, param_names, has_opts, "term()")

  """
    @doc \"\"\"
    #{String.trim(doc)}
    \"\"\"
    #{spec}
    def #{name}(#{param_list(param_names, has_opts)}) do
      #{call}
    end
  """
end

defp render_streaming_variant(name, param_names, has_opts, args) do
  # Always include opts for runtime flags access, even if Python has no optional params
  # This ensures idempotent/__runtime__ are accessible for streaming calls
  stream_params = param_names ++ ["opts \\\\ []", "callback"]
  stream_params_str = Enum.join(stream_params, ", ")

  stream_call = "SnakeBridge.Runtime.stream(__MODULE__, :#{name}, #{args}, opts, callback)"

  # Spec for streaming variant
  spec_args = Enum.map(param_names, fn _ -> "term()" end) ++ ["keyword()", "(term() -> any())"]
  spec_args_str = Enum.join(spec_args, ", ")

  """
    @doc \"\"\"
    Streaming variant of `#{name}/#{length(param_names) + (if has_opts, do: 1, else: 0)}`.

    The callback receives chunks as they arrive.
    \"\"\"
    @spec #{name}_stream(#{spec_args_str}) :: :ok | {:error, Snakepit.Error.t()}
    def #{name}_stream(#{stream_params_str}) when is_function(callback, 1) do
      #{stream_call}
    end
  """
end
```

**Files to Change:**
- `lib/snakebridge/generator.ex`:
  - `render_function/1` → `render_function/2`
  - Add `render_normal_function/5`
  - Add `render_streaming_variant/4`
  - Update `render_library/4` to pass library to `render_function/2`
  - Update `render_submodule/2` to pass library to `render_function/2`

**Call-Sites to Update:**
```elixir
# In render_library/4
function_defs =
  base_functions
  |> Enum.sort_by(& &1["name"])
  |> Enum.map_join("\n\n", &render_function(&1, library))  # Pass library

# In render_submodule/2 - needs library parameter added
defp render_submodule(python_module, functions, library) do
  # ...
  |> Enum.map_join("\n\n", &render_function(&1, library))
```

---

### 4. Stop Rewriting Unchanged Files

**The Problem:**
`File.write!` called unconditionally.

**The Fix:**

```elixir
# lib/snakebridge/generator.ex

def generate_library(library, functions, classes, config) do
  File.mkdir_p!(config.generated_dir)
  path = Path.join(config.generated_dir, "#{library.python_name}.ex")

  source =
    render_library(library, functions, classes, version: Application.spec(:snakebridge, :vsn))

  # Only write if content changed
  write_if_changed(path, source)

  # Preserve original return type
  :ok
end

defp write_if_changed(path, new_content) do
  case File.read(path) do
    {:ok, existing} when existing == new_content ->
      :unchanged

    _ ->
      # Atomic write with unique temp file for concurrency safety
      # Using unique integer prevents collisions from parallel compiles
      temp_path = "#{path}.tmp.#{System.unique_integer([:positive])}"

      try do
        File.write!(temp_path, new_content)
        File.rename!(temp_path, path)
        :written
      after
        # Clean up temp file if rename failed
        File.rm(temp_path)
      end
  end
end
```

**Files to Change:**
- `lib/snakebridge/generator.ex` - `generate_library/4`, add `write_if_changed/2`

**Note:** The return value of `write_if_changed/2` (`:unchanged` vs `:written`) is discarded to preserve the original `:ok` contract. This can be used for telemetry in future.

---

### 5. Strengthen Strict Mode (Phased Approach)

**The Problem:**
Strict mode only checks manifest presence, not generated file integrity.

**Recommended Phased Implementation:**

**Phase 1 (MVP):** File existence check
**Phase 2:** Symbol presence verification (scan generated files)
**Phase 3:** Content hash validation (requires manifest changes)
**Phase 4:** Lock identity verification

**The Fix (Phase 1 + 2):**

```elixir
# lib/mix/tasks/compile/snakebridge.ex

defp run_strict(config) do
  manifest = Manifest.load(config)

  # Phase 1: All detected symbols in manifest
  detected = scanner_module().scan_project(config)
  missing = Manifest.missing(manifest, detected)

  if missing != [] do
    raise_missing_symbols_error(missing)
  end

  # Phase 2: All generated files exist
  verify_generated_files_exist!(config)

  # Phase 2b: Verify symbols are present in generated files
  verify_symbols_present!(config, manifest)

  {:ok, []}
end

defp verify_generated_files_exist!(config) do
  Enum.each(config.libraries, fn library ->
    path = Path.join(config.generated_dir, "#{library.python_name}.ex")

    unless File.exists?(path) do
      raise SnakeBridge.CompileError, """
      Strict mode: Generated file missing: #{path}

      Run `mix compile` locally and commit the generated files.
      """
    end
  end)
end

defp verify_symbols_present!(config, manifest) do
  symbols = Map.get(manifest, "symbols", %{})

  Enum.each(config.libraries, fn library ->
    path = Path.join(config.generated_dir, "#{library.python_name}.ex")

    case File.read(path) do
      {:ok, content} ->
        # Check that expected function definitions exist
        expected_functions =
          symbols
          |> Map.values()
          |> Enum.filter(fn info ->
            String.starts_with?(info["python_module"] || "", library.python_name)
          end)
          |> Enum.map(& &1["name"])

        missing_in_file = Enum.reject(expected_functions, fn name ->
          String.contains?(content, "def #{name}(")
        end)

        if missing_in_file != [] do
          raise SnakeBridge.CompileError, """
          Strict mode: Generated file #{path} is missing expected functions:
          #{Enum.map_join(missing_in_file, "\n", &"  - #{&1}")}

          Run `mix compile` locally to regenerate and commit the updated files.
          """
        end

      {:error, reason} ->
        raise SnakeBridge.CompileError, """
        Strict mode: Cannot read generated file #{path}: #{inspect(reason)}
        """
    end
  end)
end
```

**Future Phases (documented for completeness):**

**Phase 3 - Content hash validation:**
```elixir
# Requires manifest change:
# manifest["generated_hashes"] = %{
#   "lib/snakebridge_generated/numpy.ex" => "sha256:abc123..."
# }

defp verify_content_hashes!(config, manifest) do
  hashes = Map.get(manifest, "generated_hashes", %{})

  Enum.each(hashes, fn {path, expected_hash} ->
    actual_hash = hash_file(path)
    if actual_hash != expected_hash do
      raise SnakeBridge.CompileError, "Content hash mismatch for #{path}"
    end
  end)
end
```

**Phase 4 - Lock identity verification:**
```elixir
defp verify_lock_identity!(config) do
  case Lock.load() do
    nil ->
      raise SnakeBridge.CompileError, "Lock file missing in strict mode"

    lock ->
      current_identity = Lock.build_hardware_section()
      lock_identity = get_in(lock, ["environment", "hardware"])

      if lock_identity["platform"] != current_identity["platform"] do
        Mix.shell().info("Warning: Platform mismatch detected")
        # Optionally fail in strict mode
      end
  end
end
```

**Files to Change:**
- `lib/mix/tasks/compile/snakebridge.ex` - `run_strict/1`, add verification functions
- (Phase 3) `lib/snakebridge/manifest.ex` - add hash tracking
- (Phase 3) `lib/snakebridge/generator.ex` - compute and store hashes

---

## P1: High-Value Improvements

### 6. Wire Documentation Pipeline

**The Fix:**

```elixir
# lib/snakebridge/generator.ex

defp format_docstring(nil), do: ""
defp format_docstring(""), do: ""

defp format_docstring(raw_doc) do
  raw_doc
  |> SnakeBridge.Docs.RstParser.parse()
  |> SnakeBridge.Docs.MarkdownConverter.convert()
rescue
  # Fall back to raw doc if parsing fails
  _ -> raw_doc
end

# Update render_function to use format_docstring
defp render_normal_function(name, param_names, has_opts, args, doc) do
  formatted_doc = format_docstring(doc)
  # ... rest of function
end
```

---

### 7. Use TypeMapper for Specs

**The Fix:**
1. Add annotation string parser to convert `"int"` → `%{"type" => "int"}`
2. Use TypeMapper in `function_spec/4`

Requires bridging the annotation string format to TypeMapper's expected structure.

```elixir
# lib/snakebridge/generator.ex

defp parse_annotation(nil), do: nil
defp parse_annotation(""), do: nil
defp parse_annotation(annotation) when is_binary(annotation) do
  # Simple parser - expand as needed
  case String.downcase(annotation) do
    "int" -> %{"type" => "int"}
    "float" -> %{"type" => "float"}
    "str" -> %{"type" => "str"}
    "bool" -> %{"type" => "bool"}
    "none" -> %{"type" => "none"}
    # Handle list[T], Optional[T], etc.
    _ -> nil
  end
end

defp param_to_spec(param) do
  case parse_annotation(param["annotation"]) do
    nil -> quote(do: term())
    type_dict -> SnakeBridge.Generator.TypeMapper.to_spec(type_dict)
  end
end
```

---

### 8. Add Telemetry Emission

**The Fix:**
Wrap `run_normal/1` with telemetry calls as shown in Gap #10 analysis.

---

### 9. Add Missing Mix Tasks

Priority order:
1. `mix snakebridge.generate` - Most useful for CI
2. `mix snakebridge.prune` - Manifest hygiene
3. Others as needed

---

## Implementation Order

**Prioritization Note:** All P0 items are ship-blockers. The order below reflects implementation dependencies and user-facing impact, not priority level.

1. **First:** Fix #1 (wrapper args) + #2 (constructors)
   - These are the most visible issues
   - Fix #1 must be decided before #2 and #3 (opts design affects all)

2. **Second:** Fix #4 (file rewriting) + #5 (strict mode phase 1-2)
   - Build reliability
   - Independent of wrapper changes

3. **Third:** Fix #3 (streaming)
   - Depends on Fix #1 decision (opts handling)
   - Feature completeness

4. **Fourth:** P1 items (#6-#9)
   - Polish and improvements

Each fix is independent and can be merged separately.

---

## Testing Strategy

For each fix, add tests that verify:

1. **Wrapper Args:**
   - Generate wrapper for function with defaulted `POSITIONAL_OR_KEYWORD` params
   - Verify wrapper accepts keyword opts
   - (If Option A) Verify pure-positional function accepts opts

2. **Constructors:**
   - Generate class, verify `new/N` arity matches `__init__` required params
   - Verify classes with 0, 1, 2+ required params all work

3. **Streaming:**
   - Configure streaming function, verify `*_stream` variant generated
   - Verify `@spec` present and correct
   - Verify streaming variant accepts opts (for runtime flags)

4. **File Rewriting:**
   - Compile once, record content hash
   - Compile again without changes
   - Verify content hash unchanged (NOT mtime - filesystem resolution varies)
   - Verify no temp files left behind

5. **Strict Mode:**
   - Remove generated file, verify strict compile fails with actionable message
   - Modify generated file to remove a function, verify Phase 2 catches it

**Test Implementation Notes:**
- Use content-based assertions (hash compare) rather than mtime-based assertions
- Filesystem timestamp resolution varies by OS and can cause flaky tests
- Consider property-based tests for generator (many Python signatures → correct Elixir wrappers)
