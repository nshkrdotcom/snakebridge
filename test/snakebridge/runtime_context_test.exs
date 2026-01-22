defmodule SnakeBridge.RuntimeContextTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.{Runtime, RuntimeContext}

  setup do
    RuntimeContext.clear_defaults()
    :ok
  end

  test "split_opts merges runtime defaults under explicit __runtime__" do
    RuntimeContext.put_defaults(pool_name: :default_pool, timeout_profile: :ml_inference)

    {_kwargs, _idempotent, _extra_args, runtime_opts} =
      Runtime.split_opts(__runtime__: [timeout_profile: :batch_job, affinity: :strict_queue])

    assert Keyword.get(runtime_opts, :pool_name) == :default_pool
    assert Keyword.get(runtime_opts, :timeout_profile) == :batch_job
    assert Keyword.get(runtime_opts, :affinity) == :strict_queue
  end

  test "split_opts returns defaults when no __runtime__ provided" do
    RuntimeContext.put_defaults(pool_name: :test_pool)

    {_kwargs, _idempotent, _extra_args, runtime_opts} = Runtime.split_opts([])

    assert Keyword.get(runtime_opts, :pool_name) == :test_pool
  end

  test "with_runtime scopes defaults and restores previous values" do
    RuntimeContext.put_defaults(pool_name: :base_pool)

    RuntimeContext.with_runtime([timeout_profile: :ml_inference], fn ->
      defaults = RuntimeContext.get_defaults()
      assert Keyword.get(defaults, :pool_name) == :base_pool
      assert Keyword.get(defaults, :timeout_profile) == :ml_inference
    end)

    defaults = RuntimeContext.get_defaults()
    assert Keyword.get(defaults, :pool_name) == :base_pool
    refute Keyword.has_key?(defaults, :timeout_profile)
  end
end
