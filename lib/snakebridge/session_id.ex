defmodule SnakeBridge.SessionId do
  @moduledoc """
  Generate collision-resistant session identifiers.
  """

  @spec generate(String.t()) :: String.t()
  def generate(prefix \\ "snakebridge") when is_binary(prefix) do
    unique = System.unique_integer([:positive, :monotonic])
    "#{prefix}_#{unique}"
  end
end
