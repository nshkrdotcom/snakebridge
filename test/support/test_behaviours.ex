defmodule SnakeBridge.Discovery.IntrospectorBehaviour do
  @moduledoc """
  Behaviour for introspection implementations.
  """

  @callback discover(module_path :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
end

defmodule SnakeBridge.Runtime.ExecutorBehaviour do
  @moduledoc """
  Behaviour for runtime execution.
  """

  @callback execute(
              session_id :: String.t(),
              operation :: atom(),
              args :: map(),
              opts :: keyword()
            ) ::
              {:ok, term()} | {:error, term()}

  @callback execute_streaming(
              session_id :: String.t(),
              operation :: atom(),
              args :: map(),
              opts :: keyword()
            ) ::
              {:ok, Stream.t()} | {:error, term()}
end

defmodule SnakeBridge.Schema.ValidatorBehaviour do
  @moduledoc """
  Behaviour for schema validation.
  """

  @callback validate(config :: map(), schema :: map()) ::
              :ok | {:error, [String.t()]}
end
