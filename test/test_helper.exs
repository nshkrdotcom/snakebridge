# Test helper for SnakeBridge
#
# This file is run before all tests and sets up the test environment.

# Start ExUnit with options
ExUnit.start(
  # Capture logs by default (can be disabled per-test with @tag capture_log: false)
  capture_log: true,
  # Seed for deterministic test runs (override with --seed)
  seed: 0,
  # Show test times
  trace: System.get_env("TRACE") == "1",
  # Exclude tags
  exclude: [
    # Skip real Python integration tests by default
    :real_python,
    # Skip slow tests unless explicitly included
    :slow,
    # Skip external network tests
    :external
  ]
)

# Setup Mox for mocking (if using Mox)
# if Code.ensure_loaded?(Mox) do
#   Mox.defmock(SnakeBridge.MockPythonRuntime, for: SnakeBridge.RuntimeBehaviour)
# end

# Setup Mimic for runtime mocking (if using Mimic)
if Code.ensure_loaded?(Mimic) do
  Mimic.copy(Snakepit)
  Mimic.copy(System)
end

# Helper functions for tests
defmodule SnakeBridge.TestHelpers do
  @moduledoc """
  Helper functions for SnakeBridge tests.
  """

  @doc """
  Creates a temporary file for testing.
  """
  def tmp_path(suffix \\ "") do
    dir = System.tmp_dir!()
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    Path.join(dir, "snakebridge_test_#{random}#{suffix}")
  end

  @doc """
  Ensures Python is available for integration tests.
  """
  def ensure_python! do
    case System.cmd("python3", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("Using Python: #{String.trim(output)}")
        :ok

      {error, code} ->
        raise "Python not available (exit #{code}): #{error}"
    end
  end

  @doc """
  Skips test if Python is not available.
  """
  def skip_unless_python(context) do
    try do
      ensure_python!()
      context
    rescue
      _ ->
        %{context | skip: true}
    end
  end

  @doc """
  Creates a mock introspection result for testing.
  """
  def mock_introspection(library_name, opts \\ []) do
    functions =
      Keyword.get(opts, :functions, [
        %{
          "name" => "example_function",
          "args" => ["arg1", "arg2"],
          "returns" => %{"kind" => "primitive", "name" => "str"},
          "doc" => "Example function for testing"
        }
      ])

    %{
      "name" => library_name,
      "module" => Keyword.get(opts, :module, "SnakeBridge.#{Macro.camelize(library_name)}"),
      "version" => Keyword.get(opts, :version, "1.0.0"),
      "description" => Keyword.get(opts, :description, "Test library"),
      "functions" => functions
    }
  end
end
