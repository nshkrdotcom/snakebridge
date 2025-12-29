defmodule Numpy do
  @moduledoc false

  def array(x, opts \\ []) do
    SnakeBridge.Runtime.call(__MODULE__, :array, [x], opts)
  end
end
