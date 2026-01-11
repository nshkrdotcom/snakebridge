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

instance_name =
  Application.get_env(:snakepit, :instance_name) ||
    System.get_env("SNAKEPIT_INSTANCE_NAME")

if is_nil(instance_name) or instance_name == "" do
  partition = System.get_env("MIX_TEST_PARTITION")
  suffix = if partition in [nil, ""], do: "test", else: "test_p#{partition}"
  Application.put_env(:snakepit, :instance_name, "snakebridge_#{suffix}")
end

instance_token =
  Application.get_env(:snakepit, :instance_token) ||
    System.get_env("SNAKEPIT_INSTANCE_TOKEN")

if is_nil(instance_token) or instance_token == "" do
  partition = System.get_env("MIX_TEST_PARTITION")
  suffix = if partition in [nil, ""], do: "test", else: "test_p#{partition}"

  run_id =
    if Code.ensure_loaded?(Snakepit.RunID) and function_exported?(Snakepit.RunID, :generate, 0) do
      Snakepit.RunID.generate()
    else
      Integer.to_string(System.unique_integer([:positive]))
    end

  Application.put_env(:snakepit, :instance_token, "snakebridge_#{suffix}_#{run_id}")
end

# Helper functions for tests are defined in test/support/test_helpers.ex
