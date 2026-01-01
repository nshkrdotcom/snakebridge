defmodule SnakeBridge.RuntimeTimeoutTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Defaults
  alias SnakeBridge.Runtime

  setup do
    # Store original config
    original_runtime = Application.get_env(:snakebridge, :runtime)

    on_exit(fn ->
      restore_env(:snakebridge, :runtime, original_runtime)
    end)

    # Clear runtime config for each test
    Application.delete_env(:snakebridge, :runtime)
    :ok
  end

  describe "Defaults.runtime_timeout_profile/1" do
    test "returns :default for :call by default" do
      assert Defaults.runtime_timeout_profile(:call) == :default
    end

    test "returns :streaming for :stream by default" do
      assert Defaults.runtime_timeout_profile(:stream) == :streaming
    end

    test "respects configured timeout_profile" do
      Application.put_env(:snakebridge, :runtime, timeout_profile: :ml_inference)
      assert Defaults.runtime_timeout_profile(:call) == :ml_inference
    end
  end

  describe "Defaults.runtime_profiles/0" do
    test "returns default profiles" do
      profiles = Defaults.runtime_profiles()

      assert is_map(profiles)
      assert Map.has_key?(profiles, :default)
      assert Map.has_key?(profiles, :streaming)
      assert Map.has_key?(profiles, :ml_inference)
      assert Map.has_key?(profiles, :batch_job)
    end

    test "default profile has 120s timeout" do
      profiles = Defaults.runtime_profiles()
      assert profiles[:default][:timeout] == 120_000
    end

    test "ml_inference profile has 600s timeout" do
      profiles = Defaults.runtime_profiles()
      assert profiles[:ml_inference][:timeout] == 600_000
    end

    test "batch_job profile has infinity timeout" do
      profiles = Defaults.runtime_profiles()
      assert profiles[:batch_job][:timeout] == :infinity
    end

    test "streaming profile has stream_timeout" do
      profiles = Defaults.runtime_profiles()
      assert profiles[:streaming][:stream_timeout] == 1_800_000
    end

    test "custom profiles override defaults" do
      custom_profiles = %{
        default: [timeout: 60_000],
        custom: [timeout: 300_000]
      }

      Application.put_env(:snakebridge, :runtime, profiles: custom_profiles)
      profiles = Defaults.runtime_profiles()

      assert profiles[:default][:timeout] == 60_000
      assert profiles[:custom][:timeout] == 300_000
    end
  end

  describe "Defaults.runtime_default_timeout/0" do
    test "returns 120_000 by default" do
      assert Defaults.runtime_default_timeout() == 120_000
    end

    test "respects configured default_timeout" do
      Application.put_env(:snakebridge, :runtime, default_timeout: 300_000)
      assert Defaults.runtime_default_timeout() == 300_000
    end
  end

  describe "Defaults.runtime_default_stream_timeout/0" do
    test "returns 1_800_000 (30 min) by default" do
      assert Defaults.runtime_default_stream_timeout() == 1_800_000
    end

    test "respects configured default_stream_timeout" do
      Application.put_env(:snakebridge, :runtime, default_stream_timeout: 3_600_000)
      assert Defaults.runtime_default_stream_timeout() == 3_600_000
    end
  end

  describe "Defaults.runtime_library_profiles/0" do
    test "returns empty map by default" do
      assert Defaults.runtime_library_profiles() == %{}
    end

    test "respects configured library_profiles" do
      library_profiles = %{
        "transformers" => :ml_inference,
        "torch" => :batch_job
      }

      Application.put_env(:snakebridge, :runtime, library_profiles: library_profiles)
      assert Defaults.runtime_library_profiles() == library_profiles
    end
  end

  describe "Runtime.apply_runtime_defaults/3" do
    test "applies default timeout when no runtime_opts provided" do
      payload = %{"library" => "numpy"}
      result = Runtime.apply_runtime_defaults(nil, payload, :call)

      assert Keyword.get(result, :timeout) == 120_000
      assert Keyword.get(result, :timeout_profile) == :default
    end

    test "applies streaming defaults for :stream call_kind" do
      payload = %{"library" => "numpy"}
      result = Runtime.apply_runtime_defaults(nil, payload, :stream)

      assert Keyword.get(result, :stream_timeout) == 1_800_000
      assert Keyword.get(result, :timeout_profile) == :streaming
    end

    test "user timeout overrides profile default" do
      payload = %{"library" => "numpy"}
      runtime_opts = [timeout: 60_000]
      result = Runtime.apply_runtime_defaults(runtime_opts, payload, :call)

      assert Keyword.get(result, :timeout) == 60_000
    end

    test "user timeout_profile overrides default" do
      payload = %{"library" => "numpy"}
      runtime_opts = [timeout_profile: :ml_inference]
      result = Runtime.apply_runtime_defaults(runtime_opts, payload, :call)

      assert Keyword.get(result, :timeout_profile) == :ml_inference
      # ml_inference has 600s timeout
      assert Keyword.get(result, :timeout) == 600_000
    end

    test "profile alias works" do
      payload = %{"library" => "numpy"}
      runtime_opts = [profile: :batch_job]
      result = Runtime.apply_runtime_defaults(runtime_opts, payload, :call)

      assert Keyword.get(result, :timeout_profile) == :batch_job
      assert Keyword.get(result, :timeout) == :infinity
    end

    test "library_profiles sets profile for known library" do
      Application.put_env(:snakebridge, :runtime,
        library_profiles: %{"transformers" => :ml_inference}
      )

      payload = %{"library" => "transformers"}
      result = Runtime.apply_runtime_defaults(nil, payload, :call)

      assert Keyword.get(result, :timeout_profile) == :ml_inference
      assert Keyword.get(result, :timeout) == 600_000
    end

    test "user timeout_profile overrides library_profiles" do
      Application.put_env(:snakebridge, :runtime,
        library_profiles: %{"transformers" => :ml_inference}
      )

      payload = %{"library" => "transformers"}
      runtime_opts = [timeout_profile: :default]
      result = Runtime.apply_runtime_defaults(runtime_opts, payload, :call)

      assert Keyword.get(result, :timeout_profile) == :default
      assert Keyword.get(result, :timeout) == 120_000
    end

    test "preserves other runtime opts" do
      payload = %{"library" => "numpy"}
      runtime_opts = [session_id: "test-session", some_other_opt: true]
      result = Runtime.apply_runtime_defaults(runtime_opts, payload, :call)

      assert Keyword.get(result, :session_id) == "test-session"
      assert Keyword.get(result, :some_other_opt) == true
      assert Keyword.get(result, :timeout) == 120_000
    end

    test "handles empty list runtime_opts" do
      payload = %{"library" => "numpy"}
      result = Runtime.apply_runtime_defaults([], payload, :call)

      assert Keyword.get(result, :timeout) == 120_000
    end
  end

  describe "Defaults.all/0 includes runtime config" do
    test "includes runtime timeout settings" do
      all = Defaults.all()

      assert Map.has_key?(all, :runtime_default_timeout)
      assert Map.has_key?(all, :runtime_default_stream_timeout)
      assert Map.has_key?(all, :runtime_timeout_profile)
    end
  end

  defp restore_env(_app, _key, nil), do: :ok
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
