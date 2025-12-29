# Verified P0 Critical Gaps

All six P0 gaps from the original analysis have been verified as **TRUE** through code inspection.

---

## Gap #1: Generated Wrappers Cannot Pass Most Python Optional Arguments

**Status:** VERIFIED TRUE

**Claim:** `build_params/1` only enables `opts \\ []` when the signature includes `KEYWORD_ONLY` or `VAR_KEYWORD`. It does NOT treat defaulted positional-or-keyword params as "optional."

**Evidence:** `lib/snakebridge/generator.ex:228-239`

```elixir
defp build_params(params) do
  required =
    params
    |> Enum.filter(&(&1["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]))
    |> Enum.reject(&Map.has_key?(&1, "default"))

  optional =
    params
    |> Enum.filter(&(&1["kind"] in ["KEYWORD_ONLY", "VAR_KEYWORD"]))

  param_names = Enum.map(required, &sanitize_name/1)
  {param_names, optional != []}
end
```

**Analysis:**
- `has_opts` (second tuple element) is only `true` when `optional != []`
- `optional` only includes `KEYWORD_ONLY` or `VAR_KEYWORD` params
- `POSITIONAL_OR_KEYWORD` params with defaults are filtered into `required` list, then rejected based on having a default
- This means the param names list is correct, but `has_opts` will be `false` for many common Python APIs

**Impact Example:**
```python
# Python function signature
def mean(a, axis=None, dtype=None, keepdims=False):
    ...
```

All params except `a` are `POSITIONAL_OR_KEYWORD` with defaults. Since there are no `KEYWORD_ONLY` or `VAR_KEYWORD` params, the generated Elixir wrapper will be:

```elixir
def mean(a) do
  SnakeBridge.Runtime.call(__MODULE__, :mean, [a])
end
```

Users cannot pass `axis`, `dtype`, or `keepdims` options.

---

## Gap #2: Class Constructors Are Effectively Wrong

**Status:** VERIFIED TRUE

**Claim:** Every class gets hardcoded `def new(arg, opts \\ [])` regardless of actual `__init__` signature.

**Evidence:** `lib/snakebridge/generator.ex:146-149`

```elixir
@spec new(term(), keyword()) :: {:ok, Snakepit.PyRef.t()} | {:error, Snakepit.Error.t()}
def new(arg, opts \\ []) do
  SnakeBridge.Runtime.call_class(__MODULE__, :__init__, [arg], opts)
end
```

**Additional Context:**
The introspection DOES capture `__init__` parameters. From `lib/snakebridge/introspector.ex:117-131`:

```elixir
def _introspect_class(name, cls):
    methods = []
    for method_name, method in inspect.getmembers(cls, predicate=callable):
        if method_name.startswith("__") and method_name not in ["__init__"]:
            continue
        try:
            sig = inspect.signature(method)
            params = [_param_info(p) for p in sig.parameters.values() if p.name != "self"]
        except (ValueError, TypeError):
            params = []
        methods.append({
            "name": method_name,
            "parameters": params,
            ...
        })
```

The `__init__` method IS introspected and its parameters ARE captured in `class_info["methods"]`. However, `render_class/2` completely ignores this data and hardcodes a single-argument constructor.

**Impact Examples:**
- Class with `__init__(self)` (0 required args) - Cannot construct
- Class with `__init__(self, x, y)` (2 required args) - Cannot construct correctly
- Class with `__init__(self, a, b=None)` (1 required, 1 optional) - Cannot pass optional

---

## Gap #3: Streaming Is Configured But Not Generated

**Status:** VERIFIED TRUE

**Claim:** Config supports `streaming:` field but generator always emits non-streaming wrappers.

**Evidence:**

Config has streaming field - `lib/snakebridge/config.ex:39`:
```elixir
streaming: [],
```

Runtime has stream function - `lib/snakebridge/runtime.ex:40-47`:
```elixir
@spec stream(module_ref(), function_name(), args(), opts(), (term() -> any())) ::
        :ok | {:error, Snakepit.Error.t()}
def stream(module, function, args \\ [], opts \\ [], callback)
    when is_function(callback, 1) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  payload = base_payload(module, function, args ++ extra_args, kwargs, idempotent)
  runtime_client().execute_stream("snakebridge.stream", payload, callback, runtime_opts)
end
```

Generator always uses `Runtime.call` - `lib/snakebridge/generator.ex:89`:
```elixir
call = runtime_call(name, args, has_opts)
```

And `runtime_call/3` at lines 252-256:
```elixir
defp runtime_call(name, args, true),
  do: "SnakeBridge.Runtime.call(__MODULE__, :#{name}, #{args}, opts)"

defp runtime_call(name, args, false),
  do: "SnakeBridge.Runtime.call(__MODULE__, :#{name}, #{args})"
```

**Analysis:**
- No code path checks if a function is in `library.streaming`
- No `runtime_stream_call/3` function exists
- No generation of `*_stream` variants or callback-based wrappers

---

## Gap #4: Deterministic Output Undermined By Rewriting Every Compile

**Status:** VERIFIED TRUE

**Claim:** Generated files are rewritten unconditionally every compile, without content comparison or atomic writes.

**Evidence:**

Compile task calls generate_from_manifest every time - `lib/mix/tasks/compile/snakebridge.ex:326`:
```elixir
generate_from_manifest(config, updated_manifest)
```

Generator writes unconditionally - `lib/snakebridge/generator.ex:78-79`:
```elixir
File.write!(path, source)
```

**What's Missing:**
1. No content hash comparison before writing
2. No atomic writes (write to temp file, then rename)
3. No file locking for concurrent safety
4. No skip when content unchanged

**Impact:**
- Every `mix compile` touches generated `.ex` files
- Mix detects mtime change and recompiles them
- Git shows files as "modified" when content is identical
- Incremental builds are slower than necessary

---

## Gap #5: Strict Mode Is Only A Partial CI Guard

**Status:** VERIFIED TRUE

**Claim:** Strict mode only checks if detected symbols are in manifest. It does not verify generated files or content integrity.

**Evidence:** `lib/mix/tasks/compile/snakebridge.ex:285-310`

```elixir
defp run_strict(config) do
  manifest = Manifest.load(config)
  detected = scanner_module().scan_project(config)
  missing = Manifest.missing(manifest, detected)

  if missing != [] do
    # ... raise error about missing symbols
  end

  {:ok, []}
end
```

**What Strict Mode Checks:**
- Detected symbols (from source scan) that are not in manifest

**What Strict Mode Does NOT Check:**
- Generated `.ex` files exist
- Generated file content matches what manifest describes
- Lock file is consistent with current environment
- No corruption of manifest or lock files

**The Verify Task:**
`mix snakebridge.verify` (`lib/mix/tasks/snakebridge.verify.ex`) only verifies **hardware compatibility** (platform, CUDA version, GPU count), not cache/file integrity.

---

## Gap #6: Varargs (`*args`) Not Exposed

**Status:** VERIFIED TRUE

**Claim:** Runtime supports `__args__`, but codegen neither detects nor enables a wrapper shape to pass them.

**Evidence:**

Runtime extracts `__args__` - `lib/snakebridge/runtime.ex:112`:
```elixir
extra_args = Keyword.get(opts, :__args__, [])
```

But `build_params/1` ignores `VAR_POSITIONAL` - `lib/snakebridge/generator.ex:231-232`:
```elixir
required =
  params
  |> Enum.filter(&(&1["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]))
```

The `VAR_POSITIONAL` kind (Python's `*args`) is completely ignored.

**Impact:**
Functions like `print(*values, sep=' ', end='\n')` cannot accept the varargs portion from Elixir.
