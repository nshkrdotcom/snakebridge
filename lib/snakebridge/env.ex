defmodule SnakeBridge.Env do
  @moduledoc false

  @system_key {__MODULE__, :system_env}
  @app_key {__MODULE__, :app_env}

  @type restore_fun :: (-> :ok)

  @spec system_env(String.t()) :: String.t() | nil
  def system_env(key) when is_binary(key) do
    case Process.get({@system_key, key}) do
      {:set, value} -> value
      _ -> System.get_env(key)
    end
  end

  @spec app_env(atom(), atom(), term()) :: term()
  def app_env(app, key, default \\ nil) when is_atom(app) and is_atom(key) do
    case Process.get({@app_key, app, key}) do
      {:set, value} -> value
      _ -> Application.get_env(app, key, default)
    end
  end

  @spec put_system_env_override(String.t(), String.t() | nil) :: restore_fun()
  def put_system_env_override(key, value) when is_binary(key) do
    token = {@system_key, key}
    previous = Process.get(token)
    Process.put(token, {:set, value})

    fn -> restore(token, previous) end
  end

  @spec put_app_env_override(atom(), atom(), term()) :: restore_fun()
  def put_app_env_override(app, key, value) when is_atom(app) and is_atom(key) do
    token = {@app_key, app, key}
    previous = Process.get(token)
    Process.put(token, {:set, value})

    fn -> restore(token, previous) end
  end

  defp restore(token, nil), do: Process.delete(token)
  defp restore(token, previous), do: Process.put(token, previous)
end
