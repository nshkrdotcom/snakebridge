defmodule SnakeBridge.ScriptOptions do
  @moduledoc false

  @legacy_truthy ["1", "true", "yes", "y", "on"]

  @spec resolve(keyword(), map()) :: keyword()
  def resolve(opts, env \\ System.get_env()) when is_list(opts) and is_map(env) do
    opts
    |> maybe_put_exit_mode(env)
    |> Keyword.put_new(:stop_mode, :if_started)
  end

  defp maybe_put_exit_mode(opts, env) do
    cond do
      Keyword.has_key?(opts, :exit_mode) ->
        opts

      Keyword.has_key?(opts, :halt) ->
        opts

      exit_env_set?(env) ->
        opts

      true ->
        Keyword.put(opts, :exit_mode, :auto)
    end
  end

  defp exit_env_set?(env) do
    case Map.get(env, "SNAKEPIT_SCRIPT_EXIT") do
      nil ->
        legacy_halt_truthy?(env)

      value ->
        String.trim(value) != ""
    end
  end

  defp legacy_halt_truthy?(env) do
    case Map.get(env, "SNAKEPIT_SCRIPT_HALT") do
      nil -> false
      value -> String.downcase(String.trim(value)) in @legacy_truthy
    end
  end
end
