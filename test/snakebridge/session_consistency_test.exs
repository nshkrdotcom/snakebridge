defmodule SnakeBridge.SessionConsistencyTest do
  @moduledoc """
  Tests session ID consistency across all Runtime call paths.

  These tests verify that the `__runtime__: [session_id: X]` option
  is respected by ALL call paths, ensuring payload session_id and
  routing session_id are always consistent.
  """

  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  # Test module for atom module paths
  defmodule TestMathModule do
    def __snakebridge_python_name__, do: "math"
    def __snakebridge_library__, do: "math"
  end

  defmodule TestClassModule do
    def __snakebridge_python_name__, do: "sympy"
    def __snakebridge_library__, do: "sympy"
    def __snakebridge_python_class__, do: "Symbol"
  end

  setup do
    restore = SnakeBridge.TestHelpers.put_runtime_client(SnakeBridge.RuntimeClientMock)

    # Clear any existing session context
    SnakeBridge.Runtime.clear_auto_session()
    SnakeBridge.SessionContext.clear_current()

    on_exit(restore)

    :ok
  end

  @custom_session "custom_override_session_123"

  describe "call/4 atom module respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        # Payload must contain the overridden session_id
        assert payload["session_id"] == @custom_session
        # Runtime opts must also have the session_id
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, 2.0}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call(
          TestMathModule,
          :sqrt,
          [4],
          __runtime__: [session_id: @custom_session]
        )
    end

    test "without override, uses context session" do
      context_session = "context_session_456"

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == context_session
        assert Keyword.get(opts, :session_id) == context_session
        {:ok, 2.0}
      end)

      SnakeBridge.SessionContext.with_session([session_id: context_session], fn ->
        {:ok, _} = SnakeBridge.Runtime.call(TestMathModule, :sqrt, [4])
      end)
    end
  end

  describe "call_dynamic/4 respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, 2.0}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call_dynamic(
          "math",
          "sqrt",
          [4],
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "get_module_attr/3 string module respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, 3.14159}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.get_module_attr(
          "math",
          "pi",
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "get_module_attr/3 atom module respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, 3.14159}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.get_module_attr(
          TestMathModule,
          :pi,
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "call_class/4 respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session

        {:ok,
         %{
           "__type__" => "ref",
           "__schema__" => 1,
           "id" => "ref-1",
           "session_id" => @custom_session,
           "python_module" => "sympy",
           "library" => "sympy"
         }}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call_class(
          TestClassModule,
          :__init__,
          ["x"],
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "call_helper/3 with list opts respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, %{"installed" => true}}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call_helper(
          "snakebridge.ping",
          [],
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "call_helper/3 with map opts uses context session" do
    # Map opts variant cannot have __runtime__, uses context only
    test "uses context session when in SessionContext" do
      context_session = "helper_context_session"

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        assert payload["session_id"] == context_session
        {:ok, %{"installed" => true}}
      end)

      SnakeBridge.SessionContext.with_session([session_id: context_session], fn ->
        {:ok, _} = SnakeBridge.Runtime.call_helper("snakebridge.ping", [], %{})
      end)
    end
  end

  describe "stream/5 atom module respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute_stream, fn "snakebridge.stream",
                                                                payload,
                                                                _callback,
                                                                opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        :ok
      end)

      :ok =
        SnakeBridge.Runtime.stream(
          TestMathModule,
          :iter,
          [10],
          [__runtime__: [session_id: @custom_session]],
          fn _item -> :ok end
        )
    end
  end

  describe "call_method/4 respects __runtime__ session override over ref session" do
    test "runtime override takes precedence over ref's embedded session" do
      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "__schema__" => 1,
          "id" => "ref-1",
          "session_id" => "ref_embedded_session",
          "python_module" => "test",
          "library" => "test"
        })

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        # Runtime override takes precedence
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, "result"}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call_method(
          ref,
          :some_method,
          [],
          __runtime__: [session_id: @custom_session]
        )
    end

    test "without override, uses ref's embedded session" do
      ref_session = "ref_embedded_session"

      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "__schema__" => 1,
          "id" => "ref-1",
          "session_id" => ref_session,
          "python_module" => "test",
          "library" => "test"
        })

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == ref_session
        assert Keyword.get(opts, :session_id) == ref_session
        {:ok, "result"}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_method(ref, :some_method, [])
    end
  end

  describe "session override priority" do
    test "runtime_opts > ref > context > auto-session" do
      ref_session = "ref_session"
      context_session = "context_session"

      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "__schema__" => 1,
          "id" => "ref-1",
          "session_id" => ref_session,
          "python_module" => "test",
          "library" => "test"
        })

      # Test 1: Runtime opts override everything
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, "result"}
      end)

      SnakeBridge.SessionContext.with_session([session_id: context_session], fn ->
        {:ok, _} =
          SnakeBridge.Runtime.call_method(
            ref,
            :method,
            [],
            __runtime__: [session_id: @custom_session]
          )
      end)

      # Test 2: Ref session overrides context (when no runtime opts)
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == ref_session
        assert Keyword.get(opts, :session_id) == ref_session
        {:ok, "result"}
      end)

      SnakeBridge.SessionContext.with_session([session_id: context_session], fn ->
        {:ok, _} = SnakeBridge.Runtime.call_method(ref, :method, [])
      end)
    end
  end

  describe "pool_name propagation for ref operations" do
    test "ref captures pool_name and get_attr reuses it when runtime opts omit pool_name" do
      pool_name = :optimizer_pool
      session_id = "pool_session_1"

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert Keyword.get(opts, :pool_name) == pool_name
        assert payload["session_id"] == session_id

        {:ok,
         %{
           "__type__" => "ref",
           "__schema__" => 1,
           "id" => "ref-1",
           "session_id" => session_id,
           "python_module" => "builtins",
           "library" => "builtins"
         }}
      end)

      {:ok, ref} =
        SnakeBridge.Runtime.call_dynamic(
          "builtins",
          "object",
          [],
          __runtime__: [session_id: session_id, pool_name: pool_name]
        )

      assert ref.pool_name == "optimizer_pool"

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert Keyword.get(opts, :pool_name) == "optimizer_pool"
        assert payload["session_id"] == session_id
        {:ok, "value"}
      end)

      assert {:ok, "value"} = SnakeBridge.Runtime.get_attr(ref, "name")
    end
  end
end
