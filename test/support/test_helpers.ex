defmodule SnakeBridge.TestHelpers do
  @moduledoc false

  def purge_module(module) do
    :code.purge(module)
    :code.delete(module)
  end

  def purge_modules(modules) when is_list(modules) do
    Enum.each(modules, &purge_module/1)
  end
end
