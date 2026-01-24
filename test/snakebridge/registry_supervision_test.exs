defmodule SnakeBridge.RegistrySupervisionTest do
  use ExUnit.Case, async: false

  test "start_link succeeds when registry already running" do
    existing = Process.whereis(SnakeBridge.Registry)

    if existing do
      assert {:ok, ^existing} = SnakeBridge.Registry.start_link()
    else
      {:ok, pid} = Agent.start(fn -> %{} end, name: SnakeBridge.Registry)

      on_exit(fn -> Process.exit(pid, :normal) end)

      assert {:ok, ^pid} = SnakeBridge.Registry.start_link()
    end
  end
end
