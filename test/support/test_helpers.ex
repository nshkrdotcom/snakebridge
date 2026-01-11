defmodule SnakeBridge.TestHelpers do
  @moduledoc """
  Helper functions for SnakeBridge tests.
  """

  @default_timeout 1000
  @default_interval 10
  @runtime_client_key :snakebridge_runtime_client

  @doc """
  Polls a condition function until it returns true or timeout is reached.

  Returns `true` if the condition was met, `false` if timeout was reached.

  ## Options
    * `:timeout` - Maximum time to wait in milliseconds (default: 1000)
    * `:interval` - Time between polls in milliseconds (default: 10)

  ## Examples

      eventually(fn -> Process.alive?(pid) end)
      eventually(fn -> File.exists?(path) end, timeout: 5000)
  """
  def eventually(condition_fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    interval = Keyword.get(opts, :interval, @default_interval)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_eventually(condition_fun, interval, deadline)
  end

  defp do_eventually(condition_fun, interval, deadline) do
    if condition_fun.() do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(interval)
        do_eventually(condition_fun, interval, deadline)
      end
    end
  end

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
    ensure_python!()
    context
  rescue
    _ ->
      %{context | skip: true}
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

  @doc """
  Sets a per-process runtime client override and returns a restore function.
  """
  def put_runtime_client(client) do
    previous = Process.get(@runtime_client_key)
    Process.put(@runtime_client_key, client)

    fn ->
      if is_nil(previous) do
        Process.delete(@runtime_client_key)
      else
        Process.put(@runtime_client_key, previous)
      end
    end
  end

  @doc """
  Runs a function with a per-process runtime client override.
  """
  def with_runtime_client(client, fun) when is_function(fun, 0) do
    restore = put_runtime_client(client)

    try do
      fun.()
    after
      restore.()
    end
  end
end
