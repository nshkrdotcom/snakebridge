defmodule SnakeBridge.Telemetry do
  @moduledoc """
  Telemetry event definitions for SnakeBridge.

  This module provides instrumentation for compile-time operations including:
  - Source scanning
  - Python introspection
  - Code generation
  - Lock file verification

  ## Event List

  | Event | Measurements | Metadata |
  |-------|-------------|----------|
  | `[:snakebridge, :compile, :start]` | `system_time` | `libraries`, `strict` |
  | `[:snakebridge, :compile, :stop]` | `duration`, `symbols_generated`, `files_written` | `libraries`, `mode` |
  | `[:snakebridge, :compile, :exception]` | `duration` | `reason`, `stacktrace` |
  | `[:snakebridge, :scan, :stop]` | `duration`, `files_scanned`, `symbols_found` | `paths` |
  | `[:snakebridge, :introspect, :start]` | `system_time` | `library`, `batch_size` |
  | `[:snakebridge, :introspect, :stop]` | `duration`, `symbols_introspected`, `cache_hits` | `library`, `python_time` |
  | `[:snakebridge, :generate, :stop]` | `duration`, `bytes_written`, `functions_generated`, `classes_generated` | `library`, `file` |
  | `[:snakebridge, :docs, :fetch]` | `duration` | `module`, `function`, `source` |
  | `[:snakebridge, :lock, :verify]` | `duration` | `result`, `warnings` |

  ## Usage

      # Attach handlers in your application
      SnakeBridge.Telemetry.Handlers.Logger.attach()

      # Compile-time events are automatically emitted during mix compile

  """

  # ============================================================
  # COMPILATION EVENTS
  # ============================================================

  @doc """
  Emits compile start event.

  ## Measurements

  - `system_time` - System time when compilation started

  ## Metadata

  - `libraries` - List of library atoms being compiled
  - `strict` - Whether strict mode is enabled
  """
  @spec compile_start([atom()], boolean()) :: :ok
  def compile_start(libraries, strict) do
    :telemetry.execute(
      [:snakebridge, :compile, :start],
      %{system_time: System.system_time()},
      %{libraries: libraries, strict: strict}
    )
  end

  @doc """
  Emits compile stop event.

  ## Measurements

  - `duration` - Time in native units
  - `symbols_generated` - Number of symbols generated
  - `files_written` - Number of files written

  ## Metadata

  - `libraries` - List of library atoms compiled
  - `mode` - `:normal` or `:strict`
  """
  @spec compile_stop(integer(), non_neg_integer(), non_neg_integer(), [atom()], :normal | :strict) ::
          :ok
  def compile_stop(start_time, symbols, files, libraries, mode) do
    :telemetry.execute(
      [:snakebridge, :compile, :stop],
      %{
        duration: System.monotonic_time() - start_time,
        symbols_generated: symbols,
        files_written: files
      },
      %{libraries: libraries, mode: mode}
    )
  end

  @doc """
  Emits compile exception event.

  ## Measurements

  - `duration` - Time in native units

  ## Metadata

  - `reason` - The exception
  - `stacktrace` - The stacktrace
  """
  @spec compile_exception(integer(), term(), list()) :: :ok
  def compile_exception(start_time, reason, stacktrace) do
    :telemetry.execute(
      [:snakebridge, :compile, :exception],
      %{duration: System.monotonic_time() - start_time},
      %{reason: reason, stacktrace: stacktrace}
    )
  end

  # ============================================================
  # SCANNING EVENTS
  # ============================================================

  @doc """
  Emits scan stop event.

  ## Measurements

  - `duration` - Time in native units
  - `files_scanned` - Number of files scanned
  - `symbols_found` - Number of symbols found

  ## Metadata

  - `paths` - List of paths scanned
  """
  @spec scan_stop(integer(), non_neg_integer(), non_neg_integer(), [String.t()]) :: :ok
  def scan_stop(start_time, files, symbols, paths) do
    :telemetry.execute(
      [:snakebridge, :scan, :stop],
      %{
        duration: System.monotonic_time() - start_time,
        files_scanned: files,
        symbols_found: symbols
      },
      %{paths: paths}
    )
  end

  # ============================================================
  # INTROSPECTION EVENTS
  # ============================================================

  @doc """
  Emits introspect start event.

  ## Measurements

  - `system_time` - System time when introspection started

  ## Metadata

  - `library` - Library atom being introspected
  - `batch_size` - Number of symbols in this batch
  """
  @spec introspect_start(atom(), non_neg_integer()) :: :ok
  def introspect_start(library, batch_size) do
    :telemetry.execute(
      [:snakebridge, :introspect, :start],
      %{system_time: System.system_time()},
      %{library: library, batch_size: batch_size}
    )
  end

  @doc """
  Emits introspect stop event.

  ## Measurements

  - `duration` - Time in native units
  - `symbols_introspected` - Number of symbols introspected
  - `cache_hits` - Number of cache hits

  ## Metadata

  - `library` - Library atom introspected
  - `python_time` - Time spent in Python (native units)
  """
  @spec introspect_stop(integer(), atom(), non_neg_integer(), non_neg_integer(), integer()) :: :ok
  def introspect_stop(start_time, library, symbols, cache_hits, python_time) do
    :telemetry.execute(
      [:snakebridge, :introspect, :stop],
      %{
        duration: System.monotonic_time() - start_time,
        symbols_introspected: symbols,
        cache_hits: cache_hits
      },
      %{library: library, python_time: python_time}
    )
  end

  # ============================================================
  # GENERATION EVENTS
  # ============================================================

  @doc """
  Emits generate stop event.

  ## Measurements

  - `duration` - Time in native units
  - `bytes_written` - Number of bytes written
  - `functions_generated` - Number of functions generated
  - `classes_generated` - Number of classes generated

  ## Metadata

  - `library` - Library atom generated
  - `file` - File path written
  """
  @spec generate_stop(
          integer(),
          atom(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def generate_stop(start_time, library, file, bytes, functions, classes) do
    :telemetry.execute(
      [:snakebridge, :generate, :stop],
      %{
        duration: System.monotonic_time() - start_time,
        bytes_written: bytes,
        functions_generated: functions,
        classes_generated: classes
      },
      %{library: library, file: file}
    )
  end

  # ============================================================
  # DOCUMENTATION EVENTS
  # ============================================================

  @doc """
  Emits docs fetch event.

  ## Measurements

  - `duration` - Time in native units

  ## Metadata

  - `module` - Module fetched
  - `function` - Function name
  - `source` - `:cache`, `:python`, or `:metadata`
  """
  @spec docs_fetch(integer(), module(), atom(), :cache | :python | :metadata) :: :ok
  def docs_fetch(start_time, module, function, source) do
    :telemetry.execute(
      [:snakebridge, :docs, :fetch],
      %{duration: System.monotonic_time() - start_time},
      %{module: module, function: function, source: source}
    )
  end

  # ============================================================
  # LOCK FILE EVENTS
  # ============================================================

  @doc """
  Emits lock verify event.

  ## Measurements

  - `duration` - Time in native units

  ## Metadata

  - `result` - `:ok`, `:warning`, or `:error`
  - `warnings` - List of warning strings
  """
  @spec lock_verify(integer(), :ok | :warning | :error, [String.t()]) :: :ok
  def lock_verify(start_time, result, warnings \\ []) do
    :telemetry.execute(
      [:snakebridge, :lock, :verify],
      %{duration: System.monotonic_time() - start_time},
      %{result: result, warnings: warnings}
    )
  end
end
