defmodule SnakeBridge.Test.ScriptExitRunner do
  def main(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        switches: [
          exit_mode: :string,
          stop_mode: :string,
          halt: :boolean,
          raise: :boolean,
          print_after: :boolean,
          stop_snakepit: :boolean,
          prestart_snakepit: :boolean,
          assert_snakepit_running: :boolean
        ],
        aliases: [e: :exit_mode]
      )

    configure_snakepit()

    if opts[:stop_snakepit] do
      _ = Application.stop(:snakepit)
    end

    if opts[:prestart_snakepit] do
      {:ok, _} = Application.ensure_all_started(:snakepit)
    end

    script_opts =
      []
      |> maybe_put_exit_mode(opts)
      |> maybe_put_stop_mode(opts)
      |> maybe_put_halt(opts)

    SnakeBridge.run_as_script(
      fn ->
        if opts[:raise] do
          raise "boom"
        end

        :ok
      end,
      script_opts
    )

    if opts[:print_after] do
      IO.puts("SCRIPT_AFTER")
    end

    if opts[:assert_snakepit_running] && not snakepit_started?() do
      raise "Snakepit was stopped unexpectedly"
    end
  end

  defp configure_snakepit do
    Application.put_env(:snakepit, :pooling_enabled, false)
    Application.put_env(:snakepit, :environment, :prod)
    Application.put_env(:snakepit, :auto_install_python_deps, false)
  end

  defp maybe_put_exit_mode(opts, parsed) do
    case parsed[:exit_mode] do
      nil -> opts
      value -> Keyword.put(opts, :exit_mode, String.to_atom(value))
    end
  end

  defp maybe_put_stop_mode(opts, parsed) do
    case parsed[:stop_mode] do
      nil -> opts
      value -> Keyword.put(opts, :stop_mode, String.to_atom(value))
    end
  end

  defp maybe_put_halt(opts, parsed) do
    if Keyword.has_key?(parsed, :halt) do
      Keyword.put(opts, :halt, parsed[:halt])
    else
      opts
    end
  end

  defp snakepit_started? do
    Enum.any?(Application.started_applications(), fn {app, _desc, _vsn} ->
      app == :snakepit
    end)
  end
end

SnakeBridge.Test.ScriptExitRunner.main(System.argv())
