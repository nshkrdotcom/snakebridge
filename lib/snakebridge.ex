defmodule SnakeBridge do
  @moduledoc """
  Universal FFI bridge to Python.

  SnakeBridge provides two ways to call Python:

  1. **Generated wrappers** (compile-time): Type-safe, documented Elixir modules
     generated from Python library introspection.

  2. **Dynamic calls** (runtime): Direct calls to any Python module without
     code generation, using string module paths.

  ## Universal FFI API

  The universal FFI requires no code generation:

      # Call any Python function
      {:ok, result} = SnakeBridge.call("math", "sqrt", [16])

      # Get module attributes
      {:ok, pi} = SnakeBridge.get("math", "pi")

      # Work with Python objects
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])

  ## Sessions and Ref Lifecycle

  SnakeBridge automatically manages Python object sessions. Each Elixir process
  gets an isolated session, and refs are automatically cleaned up when the
  process terminates.

  ### Key Rules

  1. **Refs are session-scoped**: A ref is only valid within its session. Don't
     pass refs between processes without ensuring they share a session.

  2. **Process death triggers cleanup**: When an Elixir process dies, its session
     is released and all associated Python objects are garbage collected.

  3. **Auto-session per process**: By default, each process gets an auto-session
     (prefixed with `auto_`). Refs created in one process cannot be used from
     another without explicit session sharing.

  4. **Explicit sessions for sharing**: Use `SessionContext.with_session/2` with
     a shared `session_id` to allow multiple processes to access the same refs.

  5. **Ref TTL**: Python ref TTL is disabled by default. Enable via
     `SNAKEBRIDGE_REF_TTL_SECONDS` environment variable. When enabled, refs
     not accessed within the TTL window are cleaned up automatically.

  6. **Max refs limit**: Each session can hold up to 10,000 refs by default.
     Excess refs are pruned oldest-first. Configure via `SNAKEBRIDGE_REF_MAX`.

  ### Recommended Patterns

      # Pattern 1: Single process, automatic cleanup
      def process_data do
        {:ok, df} = SnakeBridge.call("pandas", "read_csv", ["data.csv"])
        {:ok, result} = SnakeBridge.method(df, "mean", [])
        result  # df is cleaned up when this process exits
      end

      # Pattern 2: Explicit session for long-lived refs
      def with_shared_session(session_id) do
        SnakeBridge.SessionContext.with_session([session_id: session_id], fn ->
          {:ok, model} = SnakeBridge.call("sklearn.linear_model", "LinearRegression", [])
          # Model ref can be accessed by other processes using same session_id
          model
        end)
      end

      # Pattern 3: Release refs explicitly when done
      {:ok, ref} = SnakeBridge.call("io", "StringIO", ["test"])
      # ... use ref ...
      SnakeBridge.release_ref(ref)  # Explicit cleanup

  For explicit session control, use `SnakeBridge.SessionContext.with_session/1`.

  ## Type Mapping

  | Elixir | Python |
  |--------|--------|
  | `nil` | `None` |
  | `true`/`false` | `True`/`False` |
  | integers | `int` |
  | floats | `float` |
  | strings | `str` |
  | `SnakeBridge.bytes(data)` | `bytes` |
  | lists | `list` |
  | maps | `dict` |
  | tuples | `tuple` |
  | `MapSet` | `set` |
  | atoms | tagged atom (decoded to string by default) |
  | `DateTime` | `datetime` |
  | `SnakeBridge.Ref` | Python object reference |

  ## Advanced Features (Opt-In)

  SnakeBridge includes optional compile-time features that are disabled by default:

  ### Strict Mode

  Enables compile-time verification of lock files and binding consistency.
  Enable via `config :snakebridge, strict: true` or `SNAKEBRIDGE_STRICT=1`.

  ### Lock File Verification

  Run `mix snakebridge.verify` to check that your lock file matches the current
  environment. Useful in CI/CD to catch hardware/package drift.

  ### Wheel Selection

  `SnakeBridge.WheelSelector` provides hardware-aware PyTorch wheel selection.
  Call `WheelSelector.pytorch_variant/0` to get the appropriate CUDA/CPU variant.

  ### Helper Packs

  Built-in helpers are enabled by default. Disable with:

      config :snakebridge, helper_pack_enabled: false

  ### Environment Variables

  | Variable | Default | Description |
  |----------|---------|-------------|
  | `SNAKEBRIDGE_STRICT` | `false` | Enable strict mode |
  | `SNAKEBRIDGE_VERBOSE` | `false` | Verbose logging |
  | `SNAKEBRIDGE_REF_TTL_SECONDS` | `0` | Ref TTL in seconds (0 = disabled) |
  | `SNAKEBRIDGE_REF_MAX` | `10000` | Max refs per session |
  | `SNAKEBRIDGE_STRICT_MODE` | `false` | Python strict mode (warns on ref accumulation) |
  | `SNAKEBRIDGE_STRICT_MODE_THRESHOLD` | `1000` | Strict mode warning threshold |
  """

  require SnakeBridge.WithContext

  alias SnakeBridge.{Bytes, Dynamic, Ref, Runtime, ScriptOptions}

  # ============================================================================
  # Script Execution
  # ============================================================================

  @doc """
  Runs a function as a script with Snakepit lifecycle management.

  Defaults:
  - `exit_mode: :auto` (only when no exit options/env vars are set)
  - `stop_mode: :if_started`

  `exit_mode` can also be controlled via `SNAKEPIT_SCRIPT_EXIT` when no
  exit options are provided.
  """
  @spec run_as_script((-> any()), keyword()) :: any() | {:error, term()}
  def run_as_script(fun, opts \\ []) when is_function(fun, 0) do
    Snakepit.run_as_script(
      fn ->
        ensure_started!()
        fun.()
      end,
      ScriptOptions.resolve(opts)
    )
  end

  defp ensure_started! do
    case Application.ensure_all_started(:snakebridge) do
      {:ok, _} ->
        :ok

      {:error, {app, reason}} ->
        raise "Failed to start #{app}: #{inspect(reason)}"
    end
  end

  # ============================================================================
  # Universal FFI API
  # ============================================================================

  @doc """
  Call a Python function.

  Accepts either a generated SnakeBridge module or a Python module path string.

  ## Parameters

  - `module` - A generated module atom (e.g., `Numpy`) or a module path string (e.g., `"numpy"`)
  - `function` - Function name as atom or string
  - `args` - List of positional arguments (default: `[]`)
  - `opts` - Keyword arguments passed to Python, plus:
    - `:idempotent` - Mark call as cacheable (default: `false`)
    - `:__runtime__` - Pass-through options to Snakepit (e.g., `:timeout`, `:pool_name`, `:affinity`)

  ## Examples

      # Call stdlib function
      {:ok, 4.0} = SnakeBridge.call("math", "sqrt", [16])

      # With keyword arguments
      {:ok, 3.14} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)

      # Submodule
      {:ok, path} = SnakeBridge.call("os.path", "join", ["/tmp", "file.txt"])

      # Create objects
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])

  ## Return Values

  - `{:ok, value}` - Decoded Elixir value for JSON-serializable results
  - `{:ok, %SnakeBridge.Ref{}}` - Reference for non-serializable Python objects
  - `{:error, reason}` - Error from Python

  ## Notes

  - String module paths trigger dynamic dispatch (no codegen required)
  - Sessions are automatic; refs are isolated per Elixir process
  - Non-JSON-serializable returns are wrapped in refs for safe access
  """
  @spec call(module() | String.t(), atom() | String.t(), list(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate call(module, function, args \\ [], opts \\ []), to: Runtime

  @doc """
  Call a Python function, raising on error.

  Same as `call/4` but raises on error instead of returning `{:error, reason}`.

  ## Examples

      result = SnakeBridge.call!("math", "sqrt", [16])
      # => 4.0

      # Raises on error
      SnakeBridge.call!("nonexistent_module", "fn", [])
      # ** (Snakepit.Error) ...
  """
  @spec call!(module() | String.t(), atom() | String.t(), list(), keyword()) :: term()
  def call!(module, function, args \\ [], opts \\ []) do
    case call(module, function, args, opts) do
      {:ok, result} -> result
      {:error, error} -> raise_on_error(error)
    end
  end

  @doc """
  Get a module-level attribute from Python.

  Retrieves constants, classes, or any attribute from a Python module.

  ## Parameters

  - `module` - A generated module atom or a module path string
  - `attr` - Attribute name as atom or string
  - `opts` - Runtime options

  ## Examples

      # Module constant
      {:ok, pi} = SnakeBridge.get("math", "pi")
      # => {:ok, 3.141592653589793}

      # Module-level class (returns ref)
      {:ok, path_class} = SnakeBridge.get("pathlib", "Path")

      # Nested attribute
      {:ok, sep} = SnakeBridge.get("os", "sep")
  """
  @spec get(module() | String.t(), atom() | String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate get(module, attr, opts \\ []), to: Runtime, as: :get_module_attr

  @doc """
  Get a module-level attribute, raising on error.
  """
  @spec get!(module() | String.t(), atom() | String.t(), keyword()) :: term()
  def get!(module, attr, opts \\ []) do
    case get(module, attr, opts) do
      {:ok, result} -> result
      {:error, error} -> raise_on_error(error)
    end
  end

  @doc """
  Stream results from a Python generator or iterator.

  Calls a Python function that returns an iterable and invokes the callback
  for each element.

  ## Parameters

  - `module` - Module atom or path string
  - `function` - Function name
  - `args` - Positional arguments
  - `opts` - Keyword arguments for the Python function
  - `callback` - Function called with each streamed element

  ## Examples

      # Process file in chunks
      SnakeBridge.stream("pandas", "read_csv", ["large.csv"], [chunksize: 1000], fn chunk ->
        IO.puts("Processing chunk")
      end)

      # Iterate range
      SnakeBridge.stream("builtins", "range", [10], [], fn i ->
        IO.puts("Got: \#{i}")
      end)

  ## Return Value

  - `{:ok, :done}` - Iteration completed successfully (for string module paths)
  - `:ok` - Iteration completed successfully (for atom modules)
  - `{:error, reason}` - Error during iteration
  """
  @spec stream(module() | String.t(), atom() | String.t(), list(), keyword(), (term() -> term())) ::
          :ok | {:ok, :done} | {:error, term()}
  defdelegate stream(module, function, args, opts, callback), to: Runtime

  @doc """
  Call a method on a Python object reference.

  ## Parameters

  - `ref` - A `SnakeBridge.Ref` from a previous call
  - `method` - Method name as atom or string
  - `args` - Positional arguments (default: `[]`)
  - `opts` - Keyword arguments

  ## Examples

      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])
      {:ok, resolved} = SnakeBridge.method(path, "resolve", [])

      # With arguments
      {:ok, child} = SnakeBridge.method(path, "joinpath", ["subdir", "file.txt"])

  ## Notes

  This is equivalent to `SnakeBridge.Dynamic.call/4` but with a clearer name
  for the universal FFI context.
  """
  @spec method(Ref.t(), atom() | String.t(), list(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate method(ref, method, args \\ [], opts \\ []), to: Dynamic, as: :call

  @doc """
  Call a method on a ref, raising on error.
  """
  @spec method!(Ref.t(), atom() | String.t(), list(), keyword()) :: term()
  def method!(ref, method, args \\ [], opts \\ []) do
    case method(ref, method, args, opts) do
      {:ok, result} -> result
      {:error, error} -> raise_on_error(error)
    end
  end

  @doc """
  Get an attribute from a Python object reference.

  ## Parameters

  - `ref` - A `SnakeBridge.Ref` from a previous call
  - `attr` - Attribute name as atom or string
  - `opts` - Runtime options

  ## Examples

      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/file.txt"])
      {:ok, name} = SnakeBridge.attr(path, "name")
      # => {:ok, "file.txt"}

      {:ok, parent} = SnakeBridge.attr(path, "parent")
      # => {:ok, %SnakeBridge.Ref{...}}  # parent is also a Path
  """
  @spec attr(Ref.t(), atom() | String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate attr(ref, attr, opts \\ []), to: Dynamic, as: :get_attr

  @doc """
  Get an attribute from a ref, raising on error.
  """
  @spec attr!(Ref.t(), atom() | String.t(), keyword()) :: term()
  def attr!(ref, attr, opts \\ []) do
    case attr(ref, attr, opts) do
      {:ok, result} -> result
      {:error, error} -> raise_on_error(error)
    end
  end

  defp raise_on_error(error) do
    cond do
      exception?(error) ->
        raise error

      match?(%Snakepit.Error{}, error) ->
        raise RuntimeError, message: to_string(error)

      true ->
        raise RuntimeError, message: "SnakeBridge error: #{inspect(error)}"
    end
  end

  defp exception?(error) do
    is_exception(error)
  end

  @doc """
  Set an attribute on a Python object reference.

  ## Parameters

  - `ref` - A `SnakeBridge.Ref` from a previous call
  - `attr` - Attribute name as atom or string
  - `value` - New value for the attribute
  - `opts` - Runtime options

  ## Examples

      {:ok, obj} = SnakeBridge.call("some_module", "SomeClass", [])
      {:ok, _} = SnakeBridge.set_attr(obj, "property", "new_value")
  """
  @spec set_attr(Ref.t(), atom() | String.t(), term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate set_attr(ref, attr, value, opts \\ []), to: Dynamic

  # ============================================================================
  # Type Helpers
  # ============================================================================

  @doc """
  Create a Bytes wrapper for explicit binary data.

  By default, SnakeBridge encodes UTF-8 valid strings as Python `str`.
  Use this function to explicitly send data as Python `bytes`.

  ## Examples

      # Crypto
      {:ok, hash_ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
      {:ok, hex} = SnakeBridge.method(hash_ref, "hexdigest", [])

      # Binary protocols
      {:ok, packed} = SnakeBridge.call("struct", "pack", [">I", 12345])

      # Base64
      {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])

  ## When to Use

  Python distinguishes `str` (text) from `bytes` (binary). Use `bytes/1` for:
  - Cryptographic operations (hashlib, hmac, cryptography)
  - Binary packing (struct)
  - Base64 encoding
  - Network protocols
  - File I/O in binary mode
  """
  @spec bytes(binary()) :: Bytes.t()
  def bytes(data) when is_binary(data) do
    Bytes.new(data)
  end

  # ============================================================================
  # Session Management
  # ============================================================================

  @doc """
  Get the current session ID.

  Returns the session ID for the current Elixir process. Sessions are
  automatically created on first Python call.

  ## Examples

      session_id = SnakeBridge.current_session()
      # => "auto_<0.123.0>_1703944800000"

      # With explicit session
      SnakeBridge.SessionContext.with_session(session_id: "my_session", fn ->
        SnakeBridge.current_session()
      end)
      # => "my_session"
  """
  @spec current_session() :: String.t()
  defdelegate current_session(), to: Runtime

  @doc """
  Release and clear the auto-session for the current process.

  Call this to eagerly release Python object refs when you're done with
  Python calls, rather than waiting for process termination.

  ## Examples

      {:ok, ref} = SnakeBridge.call("numpy", "array", [[1,2,3]])
      # ... use ref ...
      SnakeBridge.release_auto_session()  # Clean up now

  ## Notes

  - This releases all refs in the current process's auto-session
  - A new session is created automatically on the next Python call
  - Use `SessionContext.with_session/1` for more fine-grained control
  - Cleanup logs are opt-in via `config :snakebridge, session_cleanup_log_level: :debug`
  """
  @spec release_auto_session() :: :ok
  defdelegate release_auto_session(), to: Runtime

  @doc """
  Releases a Python object reference, freeing memory in the Python process.

  Call this to explicitly release a ref when you're done with it, rather than
  waiting for session cleanup or process termination.

  ## Parameters

  - `ref` - A `SnakeBridge.Ref` to release
  - `opts` - Runtime options (optional)

  ## Examples

      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
      # ... use ref ...
      :ok = SnakeBridge.release_ref(ref)

  ## Notes

  - After release, the ref is invalid and should not be used
  - Releasing an already-released ref is a no-op
  - For bulk cleanup, use `release_session/1` instead
  """
  @spec release_ref(Ref.t(), keyword()) :: :ok | {:error, term()}
  defdelegate release_ref(ref, opts \\ []), to: Runtime

  @doc """
  Releases all Python object references associated with a session.

  Use this for bulk cleanup of all refs in a session, rather than releasing
  them individually.

  ## Parameters

  - `session_id` - The session ID to release
  - `opts` - Runtime options (optional)

  ## Examples

      session_id = SnakeBridge.current_session()
      # ... create many refs ...
      :ok = SnakeBridge.release_session(session_id)

  ## Notes

  - After release, all refs from that session are invalid
  - The session can still be reused for new calls
  - For auto-sessions, prefer `release_auto_session/0`
  """
  @spec release_session(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate release_session(session_id, opts \\ []), to: Runtime

  # ============================================================================
  # Ref Utilities
  # ============================================================================

  @doc """
  Check if a value is a Python object reference.

  ## Examples

      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      SnakeBridge.ref?(path)
      # => true

      SnakeBridge.ref?("string")
      # => false
  """
  @spec ref?(term()) :: boolean()
  defdelegate ref?(value), to: Ref

  # ============================================================================
  # Helpers & Macros (Existing)
  # ============================================================================

  @doc """
  Call a helper function.
  """
  defdelegate call_helper(helper, args \\ [], opts \\ []), to: Runtime

  @doc """
  Context manager macro for Python with statements.
  """
  defmacro with_python(ref, do: block) do
    quote do
      require SnakeBridge.WithContext
      SnakeBridge.WithContext.with_python(unquote(ref), do: unquote(block))
    end
  end

  @doc """
  Returns the SnakeBridge version.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end
end
