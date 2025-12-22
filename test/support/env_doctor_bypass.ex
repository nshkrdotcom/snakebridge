defmodule SnakeBridge.EnvDoctorBypass do
  @moduledoc false

  # No-op env doctor for tests to avoid external Python checks.
  def ensure_python!(_opts \\ []), do: :ok
end
