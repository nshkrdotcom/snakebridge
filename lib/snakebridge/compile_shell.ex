defmodule SnakeBridge.CompileShell do
  @moduledoc false
  @behaviour Mix.Shell

  @compile_hint "Elixir compilation can take a bit; thanks for your patience."
  @compile_hint_key {__MODULE__, :compile_hint_printed}
  @delegate_key {__MODULE__, :delegate}

  def install do
    if Code.ensure_loaded?(Mix) do
      if Mix.shell() != __MODULE__ do
        :persistent_term.put(@delegate_key, Mix.shell())
        Mix.shell(__MODULE__)
      end
    end
  end

  @impl Mix.Shell
  def info(message) do
    delegate().info(message)
    maybe_print_hint(message)
  end

  @impl Mix.Shell
  def error(message), do: delegate().error(message)

  @impl Mix.Shell
  def cmd(command), do: delegate().cmd(command)

  @impl Mix.Shell
  def cmd(command, options), do: delegate().cmd(command, options)

  @impl Mix.Shell
  def prompt(message), do: delegate().prompt(message)

  @impl Mix.Shell
  def yes?(message), do: delegate().yes?(message)

  @impl Mix.Shell
  def yes?(message, options), do: delegate().yes?(message, options)

  @impl Mix.Shell
  def print_app, do: delegate().print_app()

  defp maybe_print_hint(message) when is_binary(message) do
    if String.starts_with?(message, "Compiling ") and not hint_printed?() do
      :persistent_term.put(@compile_hint_key, true)
      delegate().info(@compile_hint)
    end
  end

  defp maybe_print_hint(_message), do: :ok

  defp hint_printed? do
    :persistent_term.get(@compile_hint_key, false)
  end

  defp delegate do
    :persistent_term.get(@delegate_key, Mix.Shell.IO)
  end
end
