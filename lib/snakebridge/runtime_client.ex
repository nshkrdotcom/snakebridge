defmodule SnakeBridge.RuntimeClient do
  @moduledoc """
  Behaviour for runtime clients that execute SnakeBridge payloads.

  The default runtime client is `Snakepit`, but tests can override
  this via the `:runtime_client` config.
  """

  @type tool :: String.t()
  @type payload :: map()
  @type opts :: keyword()
  @type callback :: (term() -> any())

  @callback execute(tool(), payload(), opts()) ::
              {:ok, term()} | {:error, Snakepit.Error.t()}

  @callback execute_stream(tool(), payload(), callback(), opts()) ::
              :ok | {:error, Snakepit.Error.t()}
end
