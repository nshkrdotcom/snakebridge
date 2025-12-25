defmodule SnakeBridge.Generator.Introspector do
  @moduledoc """
  Introspects Python libraries to extract their API information.

  This module uses `uv` (if available) to automatically install Python packages
  in temporary environments, or falls back to the system Python.

  ## Example

      iex> SnakeBridge.Generator.Introspector.introspect("math")
      {:ok, %{
        "module" => "math",
        "functions" => [
          %{
            "name" => "sqrt",
            "type" => "function",
            "params" => [%{"name" => "x", "type" => %{"type" => "float"}}],
            "return_type" => %{"type" => "float"},
            "docstring" => "Return the square root of x."
          }
        ],
        "classes" => []
      }}

  """

  require Logger

  # Python standard library modules that don't need pip install
  @stdlib_modules ~w(
    abc aifc argparse array ast asynchat asyncio asyncore atexit audioop
    base64 bdb binascii binhex bisect builtins bz2
    calendar cgi cgitb chunk cmath cmd code codecs codeop collections
    colorsys compileall concurrent configparser contextlib contextvars copy
    copyreg crypt csv ctypes curses
    dataclasses datetime dbm decimal difflib dis distutils doctest
    email encodings enum errno
    faulthandler fcntl filecmp fileinput fnmatch fractions ftplib functools
    gc getopt getpass gettext glob graphlib grp gzip
    hashlib heapq hmac html http
    idlelib imaplib imghdr imp importlib inspect io ipaddress itertools
    json keyword
    lib2to3 linecache locale logging lzma
    mailbox mailcap marshal math mimetypes mmap modulefinder msvcrt multiprocessing
    netrc nis nntplib numbers
    operator optparse os ossaudiodev
    pathlib pdb pickle pickletools pipes pkgutil platform plistlib poplib posix
    posixpath pprint profile pstats pty pwd py_compile pyclbr pydoc
    queue quopri
    random re readline reprlib resource rlcompleter runpy
    sched secrets select selectors shelve shlex shutil signal site smtpd
    smtplib sndhdr socket socketserver spwd sqlite3 ssl stat statistics string
    stringprep struct subprocess sunau symtable sys sysconfig syslog
    tabnanny tarfile telnetlib tempfile termios test textwrap threading time
    timeit tkinter token tokenize trace traceback tracemalloc tty turtle
    turtledemo types typing
    unicodedata unittest urllib uu uuid
    venv warnings wave weakref webbrowser winreg winsound wsgiref
    xdrlib xml xmlrpc
    zipapp zipfile zipimport zlib
  )

  @type introspection_result :: %{
          required(String.t()) => String.t() | list(map()) | map(),
          optional(String.t()) => any()
        }

  @doc """
  Introspects a Python library and returns its API information.

  For standard library modules (json, math, etc.), uses system Python directly.
  For third-party packages, uses `uv run --with <package>` to automatically
  install the package in a temporary environment.

  ## Parameters

    * `library` - The name of the Python library to introspect (e.g., "math", "sympy")

  ## Returns

    * `{:ok, introspection}` - Successfully introspected the library
    * `{:error, reason}` - Failed to introspect

  ## Examples

      iex> SnakeBridge.Generator.Introspector.introspect("json")
      {:ok, %{"module" => "json", "functions" => [...], "classes" => [...]}}

      iex> SnakeBridge.Generator.Introspector.introspect("sympy")
      # Automatically installs sympy via uv, then introspects
      {:ok, %{"module" => "sympy", "functions" => [...], "classes" => [...]}}

  """
  @spec introspect(String.t()) :: {:ok, introspection_result()} | {:error, term()}
  def introspect(library) when is_binary(library) do
    script_path = get_introspect_script_path()

    case File.exists?(script_path) do
      false ->
        {:error, "Introspection script not found at #{script_path}"}

      true ->
        run_introspection(script_path, library)
    end
  end

  @doc """
  Same as `introspect/1` but raises on error.

  ## Examples

      iex> SnakeBridge.Generator.Introspector.introspect!("json")
      %{"module" => "json", "functions" => [...]}

  """
  @spec introspect!(String.t()) :: introspection_result()
  def introspect!(library) do
    case introspect(library) do
      {:ok, result} -> result
      {:error, reason} -> raise "Introspection failed: #{inspect(reason)}"
    end
  end

  # Private Functions

  @spec get_introspect_script_path() :: String.t()
  defp get_introspect_script_path do
    priv_dir = :code.priv_dir(:snakebridge)

    case priv_dir do
      {:error, :bad_name} ->
        # Fallback for development when running from source
        Path.join([File.cwd!(), "priv", "python", "introspect.py"])

      priv_path when is_list(priv_path) ->
        # :code.priv_dir returns a charlist
        Path.join([to_string(priv_path), "python", "introspect.py"])
    end
  end

  @spec run_introspection(String.t(), String.t()) ::
          {:ok, introspection_result()} | {:error, term()}
  defp run_introspection(script_path, library) do
    # Determine the base module name (e.g., "sympy.core" -> "sympy")
    base_module = library |> String.split(".") |> List.first()

    if stdlib_module?(base_module) do
      run_with_system_python(script_path, library)
    else
      run_with_uv(script_path, library, base_module)
    end
  rescue
    error ->
      {:error, "Exception during introspection: #{Exception.message(error)}"}
  end

  defp stdlib_module?(module), do: module in @stdlib_modules

  defp run_with_system_python(script_path, library) do
    python_cmd = System.find_executable("python3") || System.find_executable("python")

    if python_cmd do
      case System.cmd(python_cmd, [script_path, library, "--flat"], stderr_to_stdout: true) do
        {output, 0} ->
          parse_introspection_output(output)

        {output, exit_code} ->
          Logger.debug("Introspection failed with exit code #{exit_code}: #{output}")
          {:error, "Introspection failed: #{String.trim(output)}"}
      end
    else
      {:error, "Python executable not found in PATH"}
    end
  end

  defp run_with_uv(script_path, library, package) do
    uv_cmd = System.find_executable("uv")

    if uv_cmd do
      # Use uv run --with <package> to auto-install in temp environment
      Logger.debug("Using uv to install #{package} temporarily...")

      case System.cmd(
             uv_cmd,
             ["run", "--with", package, "python", script_path, library, "--flat"],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          parse_introspection_output(output)

        {output, exit_code} ->
          Logger.debug("uv introspection failed with exit code #{exit_code}: #{output}")

          # If uv failed, try falling back to system python
          Logger.debug("Falling back to system Python...")
          run_with_system_python(script_path, library)
      end
    else
      # No uv available, try system python and give helpful error if it fails
      case run_with_system_python(script_path, library) do
        {:ok, _} = success ->
          success

        {:error, _reason} ->
          {:error,
           "Package '#{package}' not found. Install it with: pip install #{package}\n" <>
             "Or install 'uv' for automatic dependency management: curl -LsSf https://astral.sh/uv/install.sh | sh"}
      end
    end
  end

  @spec parse_introspection_output(String.t()) ::
          {:ok, introspection_result()} | {:error, term()}
  defp parse_introspection_output(output) do
    case Jason.decode(output) do
      {:ok, %{"error" => error_msg}} ->
        {:error, error_msg}

      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.debug("Failed to parse introspection output: #{output}")
        {:error, "JSON decode error: #{Exception.message(error)}"}
    end
  end
end
