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

if Code.ensure_loaded?(Mox) do
  Mox.defmock(SnakeBridge.RuntimeClientMock, for: SnakeBridge.RuntimeClient)
  Mox.defmock(SnakeBridge.PythonRunnerMock, for: SnakeBridge.PythonRunner)
end

# Helper functions for tests are defined in test/support/test_helpers.ex
