# P1 Gaps and Nuanced Findings

These gaps are real but have nuances worth noting for prioritization.

---

## Gap #7: Docs Pipeline Not Wired

**Status:** VERIFIED TRUE

**Claim:** RstParser, MarkdownConverter, and MathRenderer exist but are not used in docs fetching or generation.

**Evidence:**

`Docs.get/2` returns raw Python docstring (`lib/snakebridge/docs.ex:82-89`):
```elixir
defp fetch_from_python(module, function) do
  python_name = python_module_name(module)
  script = doc_script()

  case python_runner().run(script, [python_name, to_string(function)], []) do
    {:ok, output} -> String.trim(output)  # Raw text, no conversion
    {:error, _} -> "Documentation unavailable."
  end
end
```

Generator injects raw docstrings (`lib/snakebridge/generator.ex:93-95`):
```elixir
@doc \"\"\"
#{String.trim(doc)}
\"\"\"
```

**What Exists But Isn't Used:**
- `SnakeBridge.Docs.RstParser` - Full parser for Google/NumPy/Sphinx/Epytext styles
- `SnakeBridge.Docs.MarkdownConverter` - Converts to ExDoc Markdown
- `SnakeBridge.Docs.MathRenderer` - Renders LaTeX math

**Nuance:** The parsing pipeline is production-ready code (well-structured, handles edge cases). Wiring it in is straightforward:

```elixir
# In generator.ex or docs.ex
doc
|> SnakeBridge.Docs.RstParser.parse()
|> SnakeBridge.Docs.MarkdownConverter.convert()
```

---

## Gap #8: TypeMapper Exists But Not Used

**Status:** VERIFIED TRUE

**Claim:** TypeMapper is comprehensive but generator emits `term()` everywhere.

**Evidence:**

Generator uses literal `term()` (`lib/snakebridge/generator.ex:259`):
```elixir
defp function_spec(name, param_names, has_opts, return_type) do
  args = Enum.map(param_names, fn _ -> "term()" end)
  ...
```

TypeMapper has full implementation (`lib/snakebridge/generator/type_mapper.ex:69-104`):
```elixir
def to_spec(%{"type" => "int"}), do: quote(do: integer())
def to_spec(%{"type" => "float"}), do: quote(do: float())
def to_spec(%{"type" => "str"}), do: quote(do: String.t())
# ... 40+ type mappings including ML types
```

**Nuance:** Introspection captures annotations as strings, not structured type dicts:
```python
info["annotation"] = _format_annotation(param.annotation)
# Returns: "int", "str", "list[int]", etc.
```

TypeMapper expects structured dicts like `%{"type" => "int"}`. There's a format mismatch that would need bridging (parse annotation strings into type dicts).

**Effort Estimate:** Medium - requires annotation string parser plus wiring.

---

## Gap #9: Mix Task Surface Is Limited

**Status:** VERIFIED TRUE

**Existing Tasks:**
1. `mix compile.snakebridge` - The compiler
2. `mix snakebridge.setup` - Python environment provisioning
3. `mix snakebridge.verify` - Hardware compatibility check

**Missing Tasks (from docs/expectations):**
- `mix snakebridge.generate` - Manual regeneration/prewarm
- `mix snakebridge.prune` - Remove stale entries
- `mix snakebridge.analyze` - Analysis/stats
- `mix snakebridge.ledger` - View dynamic call ledger
- `mix snakebridge.promote` - Promote dynamic calls to generated
- `mix snakebridge.doctor` - Diagnostic tool
- `mix snakebridge.lock` - Manual lock rebuild

**Nuance:**
- `setup` and `verify` are the critical developer workflow tasks
- The compiler handles generation automatically
- Other tasks are "nice to have" for advanced workflows

**Priority Assessment:**
- `generate` (manual prewarm) - Useful for CI prewarm, medium priority
- `prune` - Important for manifest hygiene, medium priority
- Others - Lower priority, can be added incrementally

---

## Gap #10: Telemetry Not Emitted from Compile Pipeline

**Status:** VERIFIED TRUE

**Claim:** Telemetry module defines events and handlers, but compile/introspection/generation doesn't call them.

**Evidence:**

Search for `Telemetry.` in compile task: **No matches**
```bash
grep -n "Telemetry\." lib/mix/tasks/compile/snakebridge.ex
# (no output)
```

`:telemetry.execute` only appears in:
- `lib/snakebridge/telemetry.ex` (the definitions)
- `lib/snakebridge/telemetry/runtime_forwarder.ex` (runtime forwarding)

**What Needs To Be Done:**
Add telemetry calls to `run_normal/1`:

```elixir
defp run_normal(config) do
  start_time = System.monotonic_time()
  libraries = Enum.map(config.libraries, & &1.name)
  SnakeBridge.Telemetry.compile_start(libraries, false)

  try do
    # existing logic...
    SnakeBridge.Telemetry.compile_stop(start_time, symbol_count, file_count, libraries, :normal)
  rescue
    e ->
      SnakeBridge.Telemetry.compile_exception(start_time, e, __STACKTRACE__)
      reraise e, __STACKTRACE__
  end
end
```

**Nuance:** This is a straightforward addition, not a design issue. The telemetry infrastructure is solid.

---

## Gap #11: Lockfile Contents Partially Incomplete

**Status:** VERIFIED PARTIALLY TRUE

**Claim:** `generator_hash` is just `sha256(version)`, and library hashes are nil.

**Evidence:**

Generator hash (`lib/snakebridge/lock.ex:201-203`):
```elixir
defp generator_hash do
  :crypto.hash(:sha256, version()) |> Base.encode16(case: :lower)
end
```
Only hashes version string, not generator code or introspection script.

Library entries (`lib/snakebridge/lock.ex:178-191`):
```elixir
defp libraries_lock(config) do
  config.libraries
  |> Enum.map(fn library ->
    {
      library.python_name,
      %{
        "requested" => library.version,
        "resolved" => library.version,  # Same as requested
        "hash" => nil                   # Always nil
      }
    }
  end)
  |> Map.new()
end
```

**What IS Good About The Lock:**
- Hardware section is comprehensive (accelerator, CUDA version, GPU count, CPU features)
- Platform section exists (OS, arch)
- Python packages hash IS computed (`compute_packages_hash/1` at line 149)
- `python_packages` section includes metadata from `Snakepit.PythonPackages.lock_metadata`

**Nuance:** The lock file is actually more sophisticated than minimal. The gaps are:
1. Generator hash should include generator code, not just version
2. Library `resolved` should come from actual installed version
3. Library `hash` should be wheel hash for reproducibility

For MVP, the current lock is adequate for hardware compatibility. Full reproducibility requires the enhancements noted.

---

## Additional Observations

### Attribute Setters Not Generated

The generator creates only getters for class attributes:

```elixir
defp render_attribute(attr) do
  """
      @spec #{attr}(Snakepit.PyRef.t()) :: {:ok, term()} | {:error, Snakepit.Error.t()}
      def #{attr}(ref) do
        SnakeBridge.Runtime.get_attr(ref, :#{attr})
      end
  """
end
```

But `Runtime.set_attr/4` exists and works. Adding setters would be:
```elixir
def set_#{attr}(ref, value) do
  SnakeBridge.Runtime.set_attr(ref, :#{attr}, value)
end
```

### Method Signatures Have Same Issue As Functions

`render_method/1` uses the same `build_params/1` logic, so instance methods also can't accept optional parameters properly.

### Discovery Functions Exist

Generated modules include `__functions__/0` and `__classes__/0` for discovery, which is good. The `__search__/1` function delegates to `Docs.search/2`.
