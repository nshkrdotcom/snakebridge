defmodule SnakeBridge.CompileError do
  @moduledoc """
  Error raised when strict mode detects missing bindings.
  """

  defexception [:message]
end
