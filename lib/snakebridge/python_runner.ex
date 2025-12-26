defmodule SnakeBridge.PythonRunner do
  @moduledoc """
  Behaviour for executing Python scripts in the Snakepit-configured runtime.
  """

  @type script :: String.t()
  @type args :: [String.t()]
  @type opts :: keyword()

  @callback run(script(), args(), opts()) :: {:ok, String.t()} | {:error, term()}
end
