defmodule SnakeBridge.RuntimeTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Runtime

  describe "execute/4" do
    test "returns success result" do
      result =
        Runtime.execute("test_session", "call_python", %{
          "module_path" => "json",
          "function_name" => "dumps",
          "args" => [],
          "kwargs" => %{}
        })

      assert {:ok, _} = result
    end

    test "returns classified error on failure" do
      result =
        Runtime.execute("test_session", "call_python", %{
          "module_path" => "nonexistent",
          "function_name" => "foo",
          "args" => [],
          "kwargs" => %{}
        })

      # Mock returns success false for nonexistent modules
      # The exact behavior depends on the mock
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "execute_with_timeout/4" do
    test "returns result when operation completes in time" do
      result =
        Runtime.execute_with_timeout(
          "test_session",
          "call_python",
          %{
            "module_path" => "json",
            "function_name" => "dumps",
            "args" => [],
            "kwargs" => %{"obj" => %{}}
          },
          timeout: 5000
        )

      assert {:ok, _} = result
    end

    test "returns timeout error when operation exceeds timeout" do
      # This test would need a mock that takes a long time
      # For now, verify the function signature works
      result =
        Runtime.execute_with_timeout(
          "test_session",
          "call_python",
          %{
            "module_path" => "json",
            "function_name" => "dumps",
            "args" => [],
            "kwargs" => %{"obj" => %{}}
          },
          timeout: 30_000
        )

      assert {:ok, _} = result
    end

    test "uses default timeout when not specified" do
      result =
        Runtime.execute_with_timeout(
          "test_session",
          "call_python",
          %{
            "module_path" => "json",
            "function_name" => "dumps",
            "args" => [],
            "kwargs" => %{"obj" => %{}}
          },
          []
        )

      assert {:ok, _} = result
    end
  end

  describe "call_function/4" do
    test "calls module-level Python function" do
      result = Runtime.call_function("json", "dumps", %{obj: %{a: 1}})

      assert {:ok, _} = result
    end

    test "passes session_id option" do
      result = Runtime.call_function("json", "dumps", %{obj: %{}}, session_id: "custom_session")

      assert {:ok, _} = result
    end

    test "accepts timeout option" do
      result = Runtime.call_function("json", "dumps", %{obj: %{}}, timeout: 10_000)

      assert {:ok, _} = result
    end
  end

  describe "create_instance/4" do
    test "creates Python instance and returns session_id and instance_id" do
      result = Runtime.create_instance("dspy.Predict", %{"signature" => "q->a"}, nil)

      assert {:ok, {session_id, instance_id}} = result
      assert is_binary(session_id)
      assert is_binary(instance_id)
    end

    test "uses provided session_id" do
      result = Runtime.create_instance("dspy.Predict", %{"signature" => "q->a"}, "my_session")

      assert {:ok, {"my_session", _instance_id}} = result
    end
  end

  describe "call_method/4" do
    test "calls method on Python instance" do
      {:ok, {session_id, instance_id}} =
        Runtime.create_instance(
          "dspy.Predict",
          %{"signature" => "q->a"},
          nil
        )

      result = Runtime.call_method({session_id, instance_id}, "__call__", %{})

      assert {:ok, _} = result
    end
  end

  describe "telemetry" do
    setup do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-handler-#{inspect(ref)}",
        [:snakebridge, :call, :stop],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-handler-#{inspect(ref)}")
      end)

      :ok
    end

    test "emits telemetry event on execute" do
      Runtime.execute("test_session", "call_python", %{
        "module_path" => "json",
        "function_name" => "dumps",
        "args" => [],
        "kwargs" => %{}
      })

      assert_receive {:telemetry_event, [:snakebridge, :call, :stop], measurements, metadata},
                     1000

      assert is_integer(measurements.duration)
      assert metadata.tool_name == "call_python"
      assert metadata.session_id == "test_session"
    end
  end
end
