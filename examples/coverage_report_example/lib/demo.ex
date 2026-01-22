defmodule Demo do
  require SnakeBridge

  @moduledoc """
  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    SnakeBridge.script do
      Examples.reset_failures()

      IO.puts("Coverage Report Example")
      IO.puts("-----------------------")

      step("Call documented function")
      print_result(CoverageReportExample.documented(2, 3))

      step("Call undocumented function")
      print_result(CoverageReportExample.undocumented(4))

      step("Read coverage report")

      report_path =
        Path.join([File.cwd!(), "coverage_reports", "coverage_report_example.coverage.json"])

      case File.read(report_path) do
        {:ok, body} ->
          report = Jason.decode!(body)
          summary = report["summary"] || %{}
          IO.puts("Symbols: #{summary["symbols_total"]}")
          IO.puts("Non-variadic ratio: #{summary["non_variadic_ratio"]}")
          IO.puts("Doc coverage ratio: #{summary["doc_coverage_ratio"]}")

        {:error, reason} ->
          IO.puts("Failed to read coverage report: #{inspect(reason)}")
          Examples.record_failure()
      end

      Examples.assert_no_failures!()
    end
    |> Examples.assert_script_ok()
  end

  defp step(title) do
    IO.puts("")
    IO.puts("== #{title} ==")
  end

  defp print_result({:ok, value}) do
    IO.puts("Result: {:ok, #{inspect(value)}}")
  end

  defp print_result({:error, reason}) do
    IO.puts("Result: {:error, #{inspect(reason)}}")
    Examples.record_failure()
  end

  defp print_result(other) do
    IO.puts("Result: #{inspect(other)}")
  end
end
