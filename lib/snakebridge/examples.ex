defmodule SnakeBridge.Examples do
  @moduledoc false

  @failure_key :snakebridge_example_failures

  def reset_failures do
    Process.put(@failure_key, 0)
  end

  def record_failure do
    Process.put(@failure_key, failure_count() + 1)
  end

  def failure_count do
    Process.get(@failure_key, 0)
  end

  def assert_no_failures! do
    count = failure_count()

    if count > 0 do
      raise "Example failed with #{count} unexpected error(s)."
    end
  end

  def assert_script_ok(result) do
    case result do
      {:error, reason} ->
        raise "Snakepit script failed: #{inspect(reason)}"

      _ ->
        :ok
    end
  end
end
