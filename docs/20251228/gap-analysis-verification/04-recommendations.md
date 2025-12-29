# Prioritized Fix Recommendations

Based on code verification, these are the recommended fixes in priority order.

---

## P0: Ship-Blocking Fixes

### 1. Fix Wrapper Argument Surface (HIGHEST PRIORITY)

**The Problem:**
`build_params/1` treats only `KEYWORD_ONLY`/`VAR_KEYWORD` as needing `opts`.

**The Fix:**

```elixir
# lib/snakebridge/generator.ex

defp build_params(params) do
  required =
    params
    |> Enum.filter(&(&1["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]))
    |> Enum.reject(&Map.has_key?(&1, "default"))

  # FIX: Check for ANY optional parameters, not just keyword-only
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

**Tests to Add:**
- Function with `POSITIONAL_OR_KEYWORD` defaulted params generates `opts`
- Function with `VAR_POSITIONAL` generates `opts`

---

### 2. Fix Class Constructors

**The Problem:**
All classes get `new(arg, opts \\ [])` regardless of actual `__init__` signature.

**The Fix:**

```elixir
# lib/snakebridge/generator.ex

defp render_class(class_info, library) do
  # ... existing setup ...

  # Find __init__ method to get its parameters
  init_method = Enum.find(methods, fn m -> m["name"] == "__init__" end)
  init_params = (init_method && init_method["parameters"]) || []

  # Use build_params for constructor, same as functions
  {param_names, has_opts} = build_params(init_params)

  constructor = render_constructor(param_names, has_opts)

  # ... rest of class rendering ...
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

  """
      @spec new(#{Enum.join(spec_args, ", ")}) :: {:ok, Snakepit.PyRef.t()} | {:error, Snakepit.Error.t()}
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

**The Fix:**

```elixir
# lib/snakebridge/generator.ex

defp render_function(info, library) do
  name = info["name"]
  params = info["parameters"] || []
  doc = info["docstring"] || ""

  {param_names, has_opts} = build_params(params)
  args = "[" <> Enum.join(param_names, ", ") <> "]"

  # Check if this function should have streaming variant
  is_streaming = name in (library.streaming || [])

  if is_streaming do
    render_streaming_function(name, param_names, has_opts, args, doc)
  else
    render_normal_function(name, param_names, has_opts, args, doc)
  end
end

defp render_streaming_function(name, param_names, has_opts, args, doc) do
  # Generate both normal and streaming variants
  normal = render_normal_function(name, param_names, has_opts, args, doc)

  stream_params = if has_opts do
    param_names ++ ["opts \\\\ []", "callback"]
  else
    param_names ++ ["callback"]
  end

  stream_call = if has_opts do
    "SnakeBridge.Runtime.stream(__MODULE__, :#{name}, #{args}, opts, callback)"
  else
    "SnakeBridge.Runtime.stream(__MODULE__, :#{name}, #{args}, [], callback)"
  end

  streaming = """
    @doc \"\"\"
    Streaming variant of `#{name}/#{length(param_names) + (if has_opts, do: 1, else: 0)}`.

    The callback receives chunks as they arrive.
    \"\"\"
    def #{name}_stream(#{Enum.join(stream_params, ", ")}) when is_function(callback, 1) do
      #{stream_call}
    end
  """

  normal <> "\n\n" <> streaming
end
```

**Files to Change:**
- `lib/snakebridge/generator.ex` - `render_function/1` → `render_function/2`, add streaming logic
- `lib/snakebridge/generator.ex` - `render_library/4` to pass library to render_function

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
end

defp write_if_changed(path, new_content) do
  case File.read(path) do
    {:ok, existing} when existing == new_content ->
      :unchanged

    _ ->
      # Atomic write: temp file + rename
      temp_path = path <> ".tmp"
      File.write!(temp_path, new_content)
      File.rename!(temp_path, path)
      :written
  end
end
```

**Files to Change:**
- `lib/snakebridge/generator.ex` - `generate_library/4`, add `write_if_changed/2`

---

### 5. Strengthen Strict Mode

**The Problem:**
Strict mode only checks manifest, not generated files.

**The Fix:**

```elixir
# lib/mix/tasks/compile/snakebridge.ex

defp run_strict(config) do
  manifest = Manifest.load(config)

  # Check 1: All detected symbols in manifest
  detected = scanner_module().scan_project(config)
  missing = Manifest.missing(manifest, detected)

  if missing != [] do
    raise_missing_symbols_error(missing)
  end

  # Check 2: All generated files exist and match manifest
  verify_generated_files!(config, manifest)

  {:ok, []}
end

defp verify_generated_files!(config, manifest) do
  Enum.each(config.libraries, fn library ->
    path = Path.join(config.generated_dir, "#{library.python_name}.ex")

    unless File.exists?(path) do
      raise SnakeBridge.CompileError, """
      Strict mode: Generated file missing: #{path}

      Run `mix compile` locally and commit the generated files.
      """
    end

    # Optional: verify content hash matches manifest expectation
    # This requires storing content hash in manifest
  end)
end
```

**Files to Change:**
- `lib/mix/tasks/compile/snakebridge.ex` - `run_strict/1`, add `verify_generated_files!/2`
- Optionally `lib/snakebridge/manifest.ex` - add content hash tracking

---

## P1: High-Value Improvements

### 6. Wire Documentation Pipeline

**The Fix:**
In `render_function/1`, convert docstrings:

```elixir
defp format_docstring(raw_doc) do
  raw_doc
  |> SnakeBridge.Docs.RstParser.parse()
  |> SnakeBridge.Docs.MarkdownConverter.convert()
end
```

---

### 7. Use TypeMapper for Specs

**The Fix:**
1. Parse annotation strings into type dicts
2. Use TypeMapper in `function_spec/4`

Requires bridging the annotation string format to TypeMapper's expected structure.

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

1. **Week 1:** Fix #1 (wrapper args) + #2 (constructors) - These are the most visible issues
2. **Week 2:** Fix #4 (file rewriting) + #5 (strict mode) - Build reliability
3. **Week 3:** Fix #3 (streaming) + #6 (docs pipeline) - Feature completeness
4. **Week 4:** #7 (types) + #8 (telemetry) + #9 (tasks) - Polish

Each fix is independent and can be merged separately. The order reflects user-facing impact.

---

## Testing Strategy

For each fix, add tests that verify:

1. **Wrapper Args:** Generate wrapper, check it accepts keyword opts
2. **Constructors:** Generate class, verify `new/N` matches `__init__` arity
3. **Streaming:** Configure streaming function, verify `*_stream` variant generated
4. **File Rewriting:** Compile twice, verify mtime unchanged when content same
5. **Strict Mode:** Remove generated file, verify strict compile fails

Consider property-based tests for the generator (many Python signatures → correct Elixir wrappers).
