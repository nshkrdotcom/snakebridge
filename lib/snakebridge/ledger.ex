defmodule SnakeBridge.Ledger do
  @moduledoc """
  Wrapper for recording dynamic calls through Snakepit.
  """

  @spec dynamic_call(atom() | String.t(), atom() | String.t(), list(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def dynamic_call(library, function, args, opts \\ []) do
    if function_exported?(Snakepit, :dynamic_call, 4) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Snakepit, :dynamic_call, [library, function, args, opts])
    else
      {:error, :snakepit_dynamic_call_unavailable}
    end
  end
end
