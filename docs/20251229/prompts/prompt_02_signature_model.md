# Implementation Prompt: Domain 2 - Signature & Arity Model

## Context

You are implementing critical fixes to SnakeBridge's signature and arity model. This is a **P0 blocking** domain.

## Required Reading

Before implementing, read these files in order:

### Critique Documents
1. `docs/20251229/critique/001_gpt52.md` - Sections 1, 3, 5 (arity mismatch, C-extensions, keyword-only)
2. `docs/20251229/critique/002_g3p.md` - Section B (positional vs keyword)

### Implementation Plan
3. `docs/20251229/implementation/00_master_plan.md` - Domain 2 overview

### Source Files (Elixir)
4. `lib/snakebridge/manifest.ex` - Manifest storage and missing detection (lines 32-50)
5. `lib/snakebridge/scanner.ex` - Call-site arity detection (lines 122-147)
6. `lib/mix/tasks/compile/snakebridge.ex` - required_arity function (lines 452-457)
7. `lib/snakebridge/generator.ex` - build_params and wrapper generation (lines 390-407, 521-539)
8. `lib/snakebridge/introspector.ex` - Parameter introspection script (lines 117-323)

### Source Files (Python)
9. `priv/python/snakebridge_adapter.py` - Argument decoding (lines 273-302)
10. `priv/python/introspect.py` - Standalone introspection module

### Test Files
11. `test/snakebridge/manifest_test.exs` - Manifest tests
12. `test/snakebridge/generator_test.exs` - Generator tests

## Issues to Fix

### Issue 2.1: Arity Model Mismatch (P0)
**Problem**: Manifest keys use `required_arity` but scanner reports `call_site_arity`. Calls like `lib.fun(x, y, kw: 1)` detected as `/3` but manifest entry is `/2`.
**Locations**:
- `lib/snakebridge/manifest.ex` lines 32-50
- `lib/mix/tasks/compile/snakebridge.ex` lines 452-457
**Fix**: Change from exact key match to capability range matching. Store `minimum_arity` and `maximum_arity` in manifest entries.

### Issue 2.2: C-Extension Signatures (P0)
**Problem**: When `inspect.signature` fails (C extensions like NumPy), `parameters: []` generates 0-arity wrappers that can't accept arguments.
**Location**: `lib/snakebridge/generator.ex` build_params function
**Fix**: Detect `signature_available: false` and generate variadic wrappers with convenience arities up to configurable max (default 8).

### Issue 2.3: Keyword-Only Parameter Validation (P0)
**Problem**: Required keyword-only parameters (`def func(a, *, required_kw)`) are not detected or validated.
**Location**: `lib/snakebridge/generator.ex` lines 390-407
**Fix**: Track KEYWORD_ONLY params separately. Generate docs and add runtime validation for required keyword-only arguments.

### Issue 2.4: Function Name Sanitization (P1)
**Problem**: Python function names like `class`, `def`, `if` become invalid Elixir function names.
**Location**: `lib/snakebridge/generator.ex` render_function
**Fix**: Sanitize function names, store Python→Elixir mapping in manifest, use original Python name in runtime calls.

## TDD Implementation Steps

### Step 1: Write Tests First

Create `test/snakebridge/arity_model_test.exs`:
```elixir
defmodule SnakeBridge.ArityModelTest do
  use ExUnit.Case, async: true

  describe "manifest arity range matching" do
    test "call-site arity 3 matches manifest required_arity 2 with optional params" do
      manifest = %{
        "symbols" => %{
          "Lib.func/2" => %{
            "required_arity" => 2,
            "minimum_arity" => 2,
            "maximum_arity" => 4,
            "has_var_positional" => false
          }
        }
      }

      # Call with 3 args should match function with min=2, max=4
      assert SnakeBridge.Manifest.is_call_supported?(manifest, Lib, :func, 3)
    end

    test "call-site arity 5 does not match manifest max_arity 4" do
      manifest = %{
        "symbols" => %{
          "Lib.func/2" => %{
            "required_arity" => 2,
            "minimum_arity" => 2,
            "maximum_arity" => 4
          }
        }
      }

      refute SnakeBridge.Manifest.is_call_supported?(manifest, Lib, :func, 5)
    end

    test "unbounded arity with var_positional accepts any call-site arity" do
      manifest = %{
        "symbols" => %{
          "Lib.func/1" => %{
            "required_arity" => 1,
            "minimum_arity" => 1,
            "maximum_arity" => :unbounded,
            "has_var_positional" => true
          }
        }
      }

      assert SnakeBridge.Manifest.is_call_supported?(manifest, Lib, :func, 100)
    end
  end
end
```

Create `test/snakebridge/variadic_wrapper_test.exs`:
```elixir
defmodule SnakeBridge.VariadicWrapperTest do
  use ExUnit.Case, async: true

  describe "C-extension signature handling" do
    test "empty parameters with signature_available false generates variadic" do
      info = %{
        "name" => "sqrt",
        "parameters" => [],
        "signature_available" => false
      }

      plan = SnakeBridge.Generator.build_params(info["parameters"], info)
      assert plan.is_variadic == true
      assert plan.has_args == true
      assert plan.has_opts == true
    end

    test "variadic wrapper generates multiple arity clauses" do
      # Test that generated code includes f(a), f(a, b), f(a, b, c), etc.
    end
  end
end
```

Create `test/snakebridge/keyword_only_test.exs`:
```elixir
defmodule SnakeBridge.KeywordOnlyTest do
  use ExUnit.Case, async: true

  describe "keyword-only parameter handling" do
    test "build_params identifies required keyword-only params" do
      params = [
        %{"name" => "a", "kind" => "POSITIONAL_OR_KEYWORD"},
        %{"name" => "b", "kind" => "KEYWORD_ONLY"},  # No default = required
        %{"name" => "c", "kind" => "KEYWORD_ONLY", "default" => "nil"}
      ]

      plan = SnakeBridge.Generator.build_params(params)
      assert plan.required_keyword_only == [%{"name" => "b", "kind" => "KEYWORD_ONLY"}]
      assert plan.optional_keyword_only == [%{"name" => "c", "kind" => "KEYWORD_ONLY", "default" => "nil"}]
    end
  end
end
```

### Step 2: Run Tests (Expect Failures)
```bash
mix test test/snakebridge/arity_model_test.exs
mix test test/snakebridge/variadic_wrapper_test.exs
mix test test/snakebridge/keyword_only_test.exs
```

### Step 3: Implement Fixes

#### 3.1 Add Arity Range to Manifest Entries
File: `lib/mix/tasks/compile/snakebridge.ex`

Add new function after `required_arity/1`:
```elixir
defp compute_arity_info(params) do
  required_positional = required_arity(params)
  optional_positional = params
    |> Enum.filter(&optional_positional?/1)
    |> length()
  has_var_positional = Enum.any?(params, &varargs?/1)
  has_var_keyword = Enum.any?(params, &kwargs?/1)
  required_kw_only = params
    |> Enum.filter(&keyword_only_required?/1)
    |> Enum.map(& &1["name"])
  optional_kw_only = params
    |> Enum.filter(&keyword_only_optional?/1)
    |> Enum.map(& &1["name"])

  %{
    "required_arity" => required_positional,
    "minimum_arity" => required_positional,
    "maximum_arity" => if(has_var_positional, do: :unbounded, else: required_positional + optional_positional),
    "has_var_positional" => has_var_positional,
    "has_var_keyword" => has_var_keyword,
    "required_keyword_only" => required_kw_only,
    "optional_keyword_only" => optional_kw_only
  }
end

defp optional_positional?(param) do
  param["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"] and
    Map.has_key?(param, "default")
end

defp varargs?(param), do: param["kind"] == "VAR_POSITIONAL"
defp kwargs?(param), do: param["kind"] == "VAR_KEYWORD"

defp keyword_only_required?(param) do
  param["kind"] == "KEYWORD_ONLY" and not Map.has_key?(param, "default")
end

defp keyword_only_optional?(param) do
  param["kind"] == "KEYWORD_ONLY" and Map.has_key?(param, "default")
end
```

Update `build_manifest_entries` to include arity info in entries.

#### 3.2 Add Arity Range Matching to Manifest
File: `lib/snakebridge/manifest.ex`

Add new function:
```elixir
@spec is_call_supported?(map(), module(), atom(), non_neg_integer()) :: boolean()
def is_call_supported?(manifest, module, function, call_site_arity) do
  prefix = "#{module_to_string(module)}.#{function}/"

  manifest
  |> Map.get("symbols", %{})
  |> Enum.any?(fn {key, info} ->
    if String.starts_with?(key, prefix) do
      min_arity = info["minimum_arity"] || info["required_arity"] || 0
      max_arity = info["maximum_arity"]

      cond do
        max_arity == :unbounded or max_arity == "unbounded" ->
          call_site_arity >= min_arity
        is_integer(max_arity) ->
          call_site_arity >= min_arity and call_site_arity <= max_arity
        true ->
          call_site_arity == min_arity
      end
    else
      false
    end
  end)
end
```

Update `missing/2` to use `is_call_supported?/4`.

#### 3.3 Handle C-Extension Variadic Wrappers
File: `lib/snakebridge/generator.ex`

Modify `build_params/1` to detect signature unavailability:
```elixir
def build_params(params, info \\ %{}) when is_list(params) do
  signature_available = Map.get(info, "signature_available", true)

  if params == [] and not signature_available do
    # C-extension with no inspectable signature
    %{
      required: [],
      has_args: true,
      has_opts: true,
      is_variadic: true,
      required_keyword_only: [],
      optional_keyword_only: []
    }
  else
    # Normal processing
    required = Enum.filter(params, &required_positional?/1)
    required_kw_only = Enum.filter(params, &keyword_only_required?/1)
    optional_kw_only = Enum.filter(params, &keyword_only_optional?/1)

    %{
      required: required,
      has_args: Enum.any?(params, &(optional_positional?(&1) or varargs?(&1))),
      has_opts: true,
      is_variadic: false,
      required_keyword_only: required_kw_only,
      optional_keyword_only: optional_kw_only
    }
  end
end
```

Add variadic function rendering:
```elixir
defp render_variadic_function(name, library, max_arity \\ 8) do
  clauses = for arity <- 0..max_arity do
    args = Enum.map(1..arity, &"arg#{&1}")
    args_str = Enum.join(args, ", ")
    args_list = "[#{args_str}]"

    """
    def #{name}(#{if arity > 0, do: args_str <> ", ", else: ""}opts \\\\ []) do
      SnakeBridge.Runtime.call(__MODULE__, :#{name}, #{args_list}, opts)
    end
    """
  end

  Enum.join(clauses, "\n")
end
```

#### 3.4 Add Function Name Sanitization
File: `lib/snakebridge/generator.ex`

```elixir
@reserved_words ~w(def defp defmodule do end if unless case cond for while with fn when and or not true false nil in try catch rescue after else raise throw receive)

defp sanitize_function_name(python_name) when is_binary(python_name) do
  elixir_name = python_name
    |> Macro.underscore()
    |> String.replace(~r/[^a-z0-9_?!]/, "_")
    |> ensure_valid_identifier()

  elixir_name = if elixir_name in @reserved_words do
    "py_#{elixir_name}"
  else
    elixir_name
  end

  {elixir_name, python_name}
end

defp ensure_valid_identifier(name) do
  if String.match?(name, ~r/^[a-z_][a-z0-9_?!]*$/) do
    name
  else
    "_#{name}"
  end
end
```

### Step 4: Run Tests (Expect Pass)
```bash
mix test test/snakebridge/arity_model_test.exs
mix test test/snakebridge/variadic_wrapper_test.exs
mix test test/snakebridge/keyword_only_test.exs
mix test
```

### Step 5: Run Full Quality Checks
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Step 6: Update Examples

Update `examples/signature_showcase/` to demonstrate:
- Calling functions with optional arguments
- Calling C-extension functions (if NumPy available)
- Keyword-only parameter usage
- Functions with sanitized names

Update `examples/run_all.sh` if new example added.

### Step 7: Update Documentation

Update `README.md`:
- Document arity range matching behavior
- Document C-extension handling
- Document keyword-only parameter support
- Add configuration for `variadic_max_arity`

## Acceptance Criteria

- [ ] Call-site arity matches manifest if within supported range
- [ ] C-extensions generate variadic wrappers (0-8 arities by default)
- [ ] Required keyword-only params are documented in generated code
- [ ] Reserved word function names are sanitized
- [ ] No perpetual "missing" entries for functions with optional params
- [ ] Strict mode passes when call-site arity is within range
- [ ] All existing tests pass
- [ ] New tests for this domain pass
- [ ] No dialyzer errors
- [ ] No credo warnings

## Dependencies

This domain should be implemented **after** Domain 1 (Type System) as it relies on stable type marshalling. It is required by:
- Domain 3 (Class Resolution) - class method signatures use same model
- Domain 4 (Dynamic Dispatch) - dynamic calls need arity info
