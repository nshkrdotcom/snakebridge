# PROMPT 03: Ref Lifecycle Errors + Introspection Visibility

**Target Version:** v0.8.7
**Prompt:** 3 of 4
**Estimated Effort:** Medium-High

---

## REQUIRED READING

Before implementing, read these files completely:

1. **`lib/snakebridge/error_translator.ex`** (326 lines)
   - Current error translation infrastructure
   - Pattern: `translate/2` dispatches to type-specific handlers
   - Handles: ShapeMismatchError, OutOfMemoryError, DtypeMismatchError
   - Missing: RefNotFoundError, SessionMismatchError, InvalidRefError

2. **`lib/snakebridge/introspection_error.ex`** (117 lines)
   - Structured error for Python introspection failures
   - Types: `:package_not_found`, `:import_error`, `:timeout`, `:introspection_bug`
   - Has excellent `from_python_output/2` classifier
   - Currently NOT used in normal mode compile flow

3. **`lib/mix/tasks/compile/snakebridge.ex`** (874 lines)
   - Focus on lines 65-82: `update_manifest/2` function
   - Line 78-79: `{:error, _reason} -> acc` silently swallows errors
   - Normal mode flow: lines 435-468

4. **`priv/python/snakebridge_adapter.py`** (1062 lines)
   - Line 175-191: `_extract_ref_identity/2` - raises ValueError for session mismatch
   - Line 607-623: `_resolve_ref/2` - raises KeyError for ref not found
   - Line 626-638: `_release_ref/2` - raises ValueError for invalid payload

---

## CONTEXT

This prompt addresses two related issues from the MVP research:

### Part A: Missing First-Class Ref Errors (RL-1)

**Current Behavior:**
Python raises generic exceptions for ref lifecycle failures:
- `KeyError("Unknown SnakeBridge reference: {ref_id}")` - ref not found
- `ValueError("SnakeBridge reference session mismatch")` - wrong session
- `ValueError("Invalid SnakeBridge reference payload")` - malformed ref
- `ValueError("SnakeBridge reference missing id")` - missing id field

These are NOT translated to structured Elixir errors. The `error_translator.ex` only handles ML-specific errors (shape, OOM, dtype).

**Desired Behavior:**
Create first-class error types that provide:
- Structured error data (ref_id, session_id, expected vs actual)
- Helpful error messages with context
- Pattern matching capability in user code
- Consistent with existing error infrastructure

### Part B: Introspection Errors Silently Swallowed (IF-1)

**Current Behavior:**
In `lib/mix/tasks/compile/snakebridge.ex` lines 65-82:

```elixir
defp update_manifest(manifest, targets) do
  targets
  |> Introspector.introspect_batch()
  |> Enum.reduce(manifest, fn {library, result, python_module}, acc ->
    case result do
      {:ok, infos} ->
        # ... process infos ...

      {:error, _reason} ->
        acc                           # <-- ERROR SWALLOWED HERE
    end
  end)
end
```

**Impact:**
1. User sees "Compiling SnakeBridge bindings... success"
2. Manifest is incomplete (missing failed symbols)
3. Later, user code fails with `UndefinedFunctionError`
4. No indication what went wrong during introspection

**Desired Behavior:**
- Log errors using `Mix.shell().info/1` with formatted details
- Emit telemetry events for monitoring
- Show summary at end of compilation with error count
- Continue compilation (don't fail) but make issues visible

---

## GOAL

### Success Criteria

**Part A - Ref Errors:**
1. Three new error modules exist with proper Exception implementations
2. `error_translator.ex` translates Python ref errors to structured Elixir errors
3. Python adapter uses parseable error message format
4. Existing tests pass, new tests cover translation

**Part B - Introspection Visibility:**
1. `update_manifest/2` logs each introspection failure with details
2. Telemetry event `[:snakebridge, :introspection, :error]` emitted per failure
3. Summary message shows total errors after normal mode compile
4. Existing tests pass, new test covers error visibility

**Combined:**
1. `mix test` passes
2. `mix dialyzer` clean (if project uses dialyzer)
3. `mix compile` shows introspection errors when they occur
4. CHANGELOG.md updated

---

## IMPLEMENTATION STEPS

### Part A: First-Class Ref Errors

#### Step A1: Create Error Module Tests

Create `test/snakebridge/ref_errors_test.exs`:

```elixir
defmodule SnakeBridge.RefErrorsTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.RefNotFoundError
  alias SnakeBridge.SessionMismatchError
  alias SnakeBridge.InvalidRefError

  describe "RefNotFoundError" do
    test "creates error with ref_id and session_id" do
      error = RefNotFoundError.exception(
        ref_id: "abc123",
        session_id: "session_1"
      )

      assert error.ref_id == "abc123"
      assert error.session_id == "session_1"
      assert Exception.message(error) =~ "abc123"
      assert Exception.message(error) =~ "not found"
    end

    test "message includes session context" do
      error = RefNotFoundError.exception(
        ref_id: "ref_xyz",
        session_id: "auto_<0.123.0>_12345"
      )

      assert Exception.message(error) =~ "session"
    end
  end

  describe "SessionMismatchError" do
    test "creates error with expected and actual session" do
      error = SessionMismatchError.exception(
        ref_id: "ref_123",
        expected_session: "session_a",
        actual_session: "session_b"
      )

      assert error.expected_session == "session_a"
      assert error.actual_session == "session_b"
      assert Exception.message(error) =~ "session_a"
      assert Exception.message(error) =~ "session_b"
    end
  end

  describe "InvalidRefError" do
    test "creates error with reason" do
      error = InvalidRefError.exception(reason: :missing_id)

      assert error.reason == :missing_id
      assert Exception.message(error) =~ "invalid"
    end

    test "accepts string reason" do
      error = InvalidRefError.exception(reason: "malformed payload")

      assert Exception.message(error) =~ "malformed"
    end
  end
end
```

#### Step A2: Create Error Modules

**File: `lib/snakebridge/ref_not_found_error.ex`**

```elixir
defmodule SnakeBridge.RefNotFoundError do
  @moduledoc """
  Raised when a Python object reference cannot be found in the registry.

  This typically occurs when:
  - The ref was already released via `release_ref/1`
  - The session was released via `release_session/1`
  - The ref expired due to TTL
  - The ref was evicted due to registry size limits

  ## Fields

  - `:ref_id` - The ref ID that was not found
  - `:session_id` - The session ID the ref was looked up in
  - `:message` - Human-readable error message
  """

  defexception [:ref_id, :session_id, :message]

  @type t :: %__MODULE__{
          ref_id: String.t() | nil,
          session_id: String.t() | nil,
          message: String.t()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    ref_id = Keyword.get(opts, :ref_id)
    session_id = Keyword.get(opts, :session_id)
    message = Keyword.get(opts, :message) || build_message(ref_id, session_id)

    %__MODULE__{
      ref_id: ref_id,
      session_id: session_id,
      message: message
    }
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  defp build_message(ref_id, session_id) do
    base = "SnakeBridge reference '#{ref_id || "unknown"}' not found"

    if session_id do
      base <> " in session '#{session_id}'. The ref may have been released, expired, or evicted."
    else
      base <> ". The ref may have been released, expired, or evicted."
    end
  end
end
```

**File: `lib/snakebridge/session_mismatch_error.ex`**

```elixir
defmodule SnakeBridge.SessionMismatchError do
  @moduledoc """
  Raised when a ref is used with a different session than it was created in.

  SnakeBridge refs are session-scoped: a ref created in session A cannot be
  used in session B. This error indicates a ref is being used across session
  boundaries.

  ## Fields

  - `:ref_id` - The ref ID that caused the mismatch
  - `:expected_session` - The session ID the ref belongs to
  - `:actual_session` - The session ID the ref was used in
  - `:message` - Human-readable error message
  """

  defexception [:ref_id, :expected_session, :actual_session, :message]

  @type t :: %__MODULE__{
          ref_id: String.t() | nil,
          expected_session: String.t() | nil,
          actual_session: String.t() | nil,
          message: String.t()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    ref_id = Keyword.get(opts, :ref_id)
    expected_session = Keyword.get(opts, :expected_session)
    actual_session = Keyword.get(opts, :actual_session)
    message = Keyword.get(opts, :message) || build_message(ref_id, expected_session, actual_session)

    %__MODULE__{
      ref_id: ref_id,
      expected_session: expected_session,
      actual_session: actual_session,
      message: message
    }
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  defp build_message(ref_id, expected, actual) do
    "SnakeBridge reference '#{ref_id || "unknown"}' belongs to session '#{expected || "unknown"}' " <>
      "but was used in session '#{actual || "unknown"}'. Refs cannot be shared across sessions."
  end
end
```

**File: `lib/snakebridge/invalid_ref_error.ex`**

```elixir
defmodule SnakeBridge.InvalidRefError do
  @moduledoc """
  Raised when a ref payload is malformed or invalid.

  This occurs when the ref structure is missing required fields or has
  an unrecognized format.

  ## Fields

  - `:reason` - Why the ref is invalid (atom or string)
  - `:message` - Human-readable error message
  """

  defexception [:reason, :message]

  @type t :: %__MODULE__{
          reason: atom() | String.t() | nil,
          message: String.t()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    reason = Keyword.get(opts, :reason)
    message = Keyword.get(opts, :message) || build_message(reason)

    %__MODULE__{
      reason: reason,
      message: message
    }
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  defp build_message(reason) when is_atom(reason) do
    case reason do
      :missing_id -> "Invalid SnakeBridge reference: missing 'id' field"
      :missing_type -> "Invalid SnakeBridge reference: missing '__type__' field"
      :invalid_format -> "Invalid SnakeBridge reference: unrecognized payload format"
      _ -> "Invalid SnakeBridge reference: #{reason}"
    end
  end

  defp build_message(reason) when is_binary(reason) do
    "Invalid SnakeBridge reference: #{reason}"
  end

  defp build_message(_) do
    "Invalid SnakeBridge reference"
  end
end
```

#### Step A3: Update Error Translator

Modify `lib/snakebridge/error_translator.ex` to translate ref errors.

Add to the module alias section (around line 24):

```elixir
alias SnakeBridge.{RefNotFoundError, SessionMismatchError, InvalidRefError}
```

Add new detection patterns after the dtype patterns (around line 180):

```elixir
# Ref lifecycle error detection patterns
defp ref_not_found?(message) do
  String.contains?(message, "Unknown SnakeBridge reference")
end

defp session_mismatch?(message) do
  String.contains?(message, "SnakeBridge reference session mismatch")
end

defp invalid_ref?(message) do
  String.contains?(message, "Invalid SnakeBridge reference") or
    String.contains?(message, "SnakeBridge reference missing id")
end
```

Modify `translate_message/1` (around line 92) to include ref error checks:

```elixir
@spec translate_message(String.t()) :: Exception.t() | nil
def translate_message(message) when is_binary(message) do
  cond do
    ref_not_found?(message) -> translate_ref_not_found(message)
    session_mismatch?(message) -> translate_session_mismatch(message)
    invalid_ref?(message) -> translate_invalid_ref(message)
    shape_mismatch?(message) -> translate_shape_error(message)
    oom_error?(message) -> translate_oom_error(message)
    dtype_mismatch?(message) -> translate_dtype_error(message)
    true -> nil
  end
end
```

Add translation functions:

```elixir
# Translate ref not found errors
defp translate_ref_not_found(message) do
  ref_id = extract_ref_id(message)

  RefNotFoundError.exception(
    ref_id: ref_id,
    message: message
  )
end

# Translate session mismatch errors
defp translate_session_mismatch(message) do
  SessionMismatchError.exception(
    message: message
  )
end

# Translate invalid ref errors
defp translate_invalid_ref(message) do
  reason = extract_invalid_reason(message)

  InvalidRefError.exception(
    reason: reason,
    message: message
  )
end

# Extract ref ID from error message
defp extract_ref_id(message) do
  case Regex.run(~r/reference[:\s]+['\"]?([a-f0-9]+)['\"]?/i, message) do
    [_, ref_id] -> ref_id
    nil -> nil
  end
end

# Extract invalid ref reason
defp extract_invalid_reason(message) do
  cond do
    String.contains?(message, "missing id") -> :missing_id
    String.contains?(message, "payload") -> :invalid_format
    true -> :unknown
  end
end
```

#### Step A4: Add Error Translator Tests

Create `test/snakebridge/error_translator_ref_test.exs`:

```elixir
defmodule SnakeBridge.ErrorTranslatorRefTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.ErrorTranslator
  alias SnakeBridge.{RefNotFoundError, SessionMismatchError, InvalidRefError}

  describe "ref not found translation" do
    test "translates KeyError message to RefNotFoundError" do
      message = "Unknown SnakeBridge reference: abc123def456"

      result = ErrorTranslator.translate_message(message)

      assert %RefNotFoundError{} = result
      assert result.ref_id == "abc123def456"
    end

    test "translates RuntimeError with ref not found" do
      error = %RuntimeError{message: "Unknown SnakeBridge reference: xyz789"}

      result = ErrorTranslator.translate(error)

      assert %RefNotFoundError{} = result
    end
  end

  describe "session mismatch translation" do
    test "translates session mismatch message" do
      message = "SnakeBridge reference session mismatch"

      result = ErrorTranslator.translate_message(message)

      assert %SessionMismatchError{} = result
    end
  end

  describe "invalid ref translation" do
    test "translates missing id message" do
      message = "SnakeBridge reference missing id"

      result = ErrorTranslator.translate_message(message)

      assert %InvalidRefError{} = result
      assert result.reason == :missing_id
    end

    test "translates invalid payload message" do
      message = "Invalid SnakeBridge reference payload"

      result = ErrorTranslator.translate_message(message)

      assert %InvalidRefError{} = result
      assert result.reason == :invalid_format
    end
  end
end
```

---

### Part B: Introspection Visibility

#### Step B1: Create Introspection Visibility Test

Create `test/snakebridge/introspection_visibility_test.exs`:

```elixir
defmodule SnakeBridge.IntrospectionVisibilityTest do
  use ExUnit.Case

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  # This test verifies the error reporting behavior
  # We don't actually run introspection, just test the formatting

  alias SnakeBridge.IntrospectionError

  describe "error formatting" do
    test "formats package not found error" do
      error = %IntrospectionError{
        type: :package_not_found,
        package: "nonexistent_lib",
        message: "Package 'nonexistent_lib' not found",
        suggestion: "Run: mix snakebridge.setup"
      }

      formatted = Exception.message(error)

      assert formatted =~ "Package 'nonexistent_lib' not found"
      assert formatted =~ "mix snakebridge.setup"
    end

    test "formats import error" do
      error = %IntrospectionError{
        type: :import_error,
        package: "torch",
        message: "cannot import name 'cuda' from 'torch'",
        suggestion: "Check library dependencies"
      }

      formatted = Exception.message(error)

      assert formatted =~ "cuda"
      assert formatted =~ "Check library dependencies"
    end
  end
end
```

#### Step B2: Modify update_manifest/2

In `lib/mix/tasks/compile/snakebridge.ex`, replace the `update_manifest/2` function (lines 65-82):

```elixir
defp update_manifest(manifest, targets) do
  {updated_manifest, errors} =
    targets
    |> Introspector.introspect_batch()
    |> Enum.reduce({manifest, []}, fn {library, result, python_module}, {acc, errs} ->
      case result do
        {:ok, infos} ->
          {symbol_entries, class_entries} =
            build_manifest_entries(library, python_module, infos)

          updated =
            acc
            |> Manifest.put_symbols(symbol_entries)
            |> Manifest.put_classes(class_entries)

          {updated, errs}

        {:error, reason} ->
          log_introspection_error(library, python_module, reason)
          emit_introspection_error_telemetry(library, python_module, reason)
          {acc, [{library, python_module, reason} | errs]}
      end
    end)

  if errors != [] do
    show_introspection_summary(errors)
  end

  updated_manifest
end

defp log_introspection_error(library, python_module, reason) do
  formatted = format_introspection_error(library, python_module, reason)
  Mix.shell().info(formatted)
end

defp format_introspection_error(library, python_module, reason) do
  library_name = if is_map(library), do: library.name || library.python_name, else: inspect(library)

  base = "  [warning] Introspection failed for #{library_name}"
  base = if python_module && python_module != library_name, do: base <> ".#{python_module}", else: base

  case reason do
    %{type: type, message: message, suggestion: suggestion} ->
      lines = [base, "    Error: #{message}"]
      lines = if suggestion, do: lines ++ ["    Suggestion: #{suggestion}"], else: lines
      Enum.join(lines, "\n")

    %{message: message} ->
      base <> "\n    Error: #{message}"

    message when is_binary(message) ->
      base <> "\n    Error: #{message}"

    _ ->
      base <> "\n    Error: #{inspect(reason)}"
  end
end

defp emit_introspection_error_telemetry(library, python_module, reason) do
  library_name = if is_map(library), do: library.name || library.python_name, else: inspect(library)

  error_type =
    case reason do
      %{type: type} -> type
      _ -> :unknown
    end

  :telemetry.execute(
    [:snakebridge, :introspection, :error],
    %{count: 1},
    %{
      library: library_name,
      python_module: python_module,
      error_type: error_type,
      reason: reason
    }
  )
end

defp show_introspection_summary(errors) do
  count = length(errors)

  message = """

  ================================================================================
  SnakeBridge Introspection Summary
  ================================================================================
  #{count} introspection error(s) occurred. Some symbols may be missing from
  the generated bindings.

  To resolve:
    1. Check the errors above for details
    2. Ensure Python packages are installed: mix snakebridge.setup
    3. Check for import errors in your Python dependencies
    4. Re-run: mix compile

  The compilation will continue, but affected symbols will not be available.
  ================================================================================
  """

  Mix.shell().info(message)
end
```

#### Step B3: Add Telemetry Module Update (if needed)

Check if `SnakeBridge.Telemetry` module exists and add the introspection error event if not already present. The telemetry call uses `:telemetry.execute/3` directly which is always available.

---

## NEW FILES TO CREATE

| File | Purpose |
|------|---------|
| `lib/snakebridge/ref_not_found_error.ex` | RefNotFoundError exception module |
| `lib/snakebridge/session_mismatch_error.ex` | SessionMismatchError exception module |
| `lib/snakebridge/invalid_ref_error.ex` | InvalidRefError exception module |
| `test/snakebridge/ref_errors_test.exs` | Tests for new error modules |
| `test/snakebridge/error_translator_ref_test.exs` | Tests for error translation |
| `test/snakebridge/introspection_visibility_test.exs` | Tests for introspection visibility |

---

## FILES TO MODIFY

### `lib/snakebridge/error_translator.ex`

**Line 24:** Add aliases for new error types:
```elixir
alias SnakeBridge.{RefNotFoundError, SessionMismatchError, InvalidRefError}
```

**Lines 92-99:** Modify `translate_message/1` to add ref error checks BEFORE existing checks:
```elixir
def translate_message(message) when is_binary(message) do
  cond do
    ref_not_found?(message) -> translate_ref_not_found(message)
    session_mismatch?(message) -> translate_session_mismatch(message)
    invalid_ref?(message) -> translate_invalid_ref(message)
    shape_mismatch?(message) -> translate_shape_error(message)
    # ... rest unchanged
```

**After line 180:** Add detection and translation functions for ref errors (see Step A3 above).

### `lib/mix/tasks/compile/snakebridge.ex`

**Lines 65-82:** Replace entire `update_manifest/2` function with new implementation that:
- Collects errors into accumulator
- Calls `log_introspection_error/3` for each error
- Calls `emit_introspection_error_telemetry/3` for each error
- Calls `show_introspection_summary/1` if any errors occurred

**After line 82:** Add new helper functions:
- `log_introspection_error/3`
- `format_introspection_error/3`
- `emit_introspection_error_telemetry/3`
- `show_introspection_summary/1`

### `priv/python/snakebridge_adapter.py`

**No changes required.** The existing error messages are already parseable:
- Line 617: `raise KeyError(f"Unknown SnakeBridge reference: {ref_id}")`
- Line 189: `raise ValueError("SnakeBridge reference session mismatch")`
- Line 183: `raise ValueError("Invalid SnakeBridge reference payload")`
- Line 186: `raise ValueError("SnakeBridge reference missing id")`

These messages match the patterns in the updated `error_translator.ex`.

---

## CHANGELOG UPDATE

Add to `CHANGELOG.md` under `## [Unreleased]` or create `## [0.8.7]` section:

```markdown
## [0.8.7] - 2025-12-31

### Added

- First-class ref lifecycle errors: `RefNotFoundError`, `SessionMismatchError`, `InvalidRefError`
- Error translator now converts Python ref errors to structured Elixir exceptions
- Introspection failures now logged with details during normal mode compilation
- Telemetry event `[:snakebridge, :introspection, :error]` emitted for introspection failures
- Introspection summary displayed after compilation if errors occurred

### Fixed

- Introspection errors no longer silently swallowed in normal mode compilation
- Users now see which symbols failed to introspect and why
```

---

## VERIFICATION

After implementation, verify:

### 1. All Tests Pass

```bash
mix test
```

### 2. Dialyzer Clean (if configured)

```bash
mix dialyzer
```

### 3. Error Translation Works

Create a test script or use IEx:

```elixir
# Test ref not found translation
alias SnakeBridge.ErrorTranslator

message = "Unknown SnakeBridge reference: abc123"
error = ErrorTranslator.translate_message(message)
IO.inspect(error, label: "Translated error")
# Should be %SnakeBridge.RefNotFoundError{...}
```

### 4. Introspection Errors Visible

If you have a project with a missing Python package, run:

```bash
mix compile
```

You should see:
- Warning messages for each failed introspection
- Summary at the end showing error count
- Compilation still succeeds (doesn't fail)

### 5. Telemetry Events Emitted

Attach a telemetry handler in test or IEx:

```elixir
:telemetry.attach(
  "test-handler",
  [:snakebridge, :introspection, :error],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata}, label: "Telemetry")
  end,
  nil
)
```

Then trigger an introspection failure and verify the event is emitted.

---

## NOTES

1. **Error Priority:** Ref errors are checked BEFORE ML errors in `translate_message/1` because they are more specific.

2. **Backward Compatibility:** These are purely additive changes. Existing error handling continues to work.

3. **No Python Changes:** The Python adapter already uses consistent, parseable error messages.

4. **Telemetry Pattern:** Uses `:telemetry.execute/3` directly rather than a wrapper to avoid dependencies.

5. **User Experience:** The introspection summary is intentionally prominent (with banner) so users notice it.
