defmodule SnakeBridge.TestCase do
  @moduledoc """
  ExUnit CaseTemplate for SnakeBridge tests with automatic setup/teardown.

  ## Usage

      defmodule MyApp.SomeTest do
        use SnakeBridge.TestCase, pool: :dspy_pool

        test "runs pipeline" do
          {:ok, out} = Dspy.SomeModule.some_call("x", y: 1)
          assert out != nil
        end
      end
  """

  use ExUnit.CaseTemplate

  alias SnakeBridge.{Runtime, RuntimeContext}

  using opts do
    quote do
      use ExUnit.Case, async: Keyword.get(unquote(opts), :async, false)
      @snakebridge_testcase_opts unquote(opts)
    end
  end

  setup_all do
    opts = Module.get_attribute(__MODULE__, :snakebridge_testcase_opts) || []

    if Keyword.get(opts, :configure_snakepit, true) do
      SnakeBridge.ConfigHelper.configure_snakepit!(Keyword.get(opts, :snakepit, []))
    end

    case Application.ensure_all_started(:snakebridge) do
      {:ok, _} ->
        :ok

      {:error, {app, reason}} ->
        raise "Failed to start #{app}: #{inspect(reason)}"

      {:error, reason} ->
        raise "Failed to start snakebridge: #{inspect(reason)}"
    end

    :ok
  end

  setup do
    opts = Module.get_attribute(__MODULE__, :snakebridge_testcase_opts) || []
    :ok = SnakeBridge.TestCase.setup_runtime(opts)

    on_exit(fn ->
      SnakeBridge.TestCase.cleanup_runtime()
    end)

    :ok
  end

  @doc false
  def setup_runtime(opts) do
    pool = Keyword.get(opts, :pool)
    runtime_opts = List.wrap(Keyword.get(opts, :runtime, []))

    defaults =
      if is_nil(pool) do
        runtime_opts
      else
        Keyword.merge([pool_name: pool], runtime_opts)
      end

    Runtime.clear_auto_session()
    RuntimeContext.put_defaults(defaults)
    :ok
  end

  @doc false
  def cleanup_runtime do
    Runtime.release_auto_session()
    RuntimeContext.clear_defaults()
    :ok
  end
end
