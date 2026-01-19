defmodule SnakeBridge.CoverageReport do
  @moduledoc false

  alias SnakeBridge.IntrospectionError
  alias SnakeBridge.SignatureTiers

  @spec write_reports(SnakeBridge.Config.t(), map(), list()) :: :ok
  def write_reports(config, manifest, errors) do
    output_dir = report_output_dir(config)
    File.mkdir_p!(output_dir)

    Enum.each(config.libraries, fn library ->
      report = build_report(library, manifest, errors)
      write_report_files(output_dir, library.python_name, report)
    end)

    :ok
  end

  defp report_output_dir(config) do
    report_config = config.coverage_report || []
    Keyword.get(report_config, :output_dir, Path.join(config.metadata_dir, "coverage"))
  end

  defp write_report_files(output_dir, library_name, report) do
    json_path = Path.join(output_dir, "#{library_name}.coverage.json")
    md_path = Path.join(output_dir, "#{library_name}.coverage.md")

    json = Jason.encode!(report, pretty: true)
    File.write!(json_path, json)
    File.write!(md_path, markdown_report(report))
  end

  defp build_report(library, manifest, errors) do
    {functions, methods} = library_symbols(library, manifest)
    symbols = functions ++ methods

    signature_counts = count_by(symbols, & &1.signature_source)
    doc_counts = count_by(symbols, & &1.doc_source)
    stub_sources = stub_sources(symbols)

    issues =
      symbols
      |> Enum.flat_map(&symbol_issues/1)
      |> Kernel.++(library_errors(library, errors))

    %{
      "library" => library.python_name,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "summary" => %{
        "symbols_total" => length(symbols),
        "functions" => length(functions),
        "class_methods" => length(methods),
        "signature_tiers" => signature_counts,
        "doc_tiers" => doc_counts,
        "non_variadic_ratio" => non_variadic_ratio(symbols),
        "doc_coverage_ratio" => doc_coverage_ratio(symbols)
      },
      "stubs" => %{
        "count" => length(stub_sources),
        "sources" => stub_sources
      },
      "issues" => issues
    }
  end

  defp library_symbols(library, manifest) do
    functions =
      manifest
      |> Map.get("symbols", %{})
      |> Map.values()
      |> Enum.filter(fn info ->
        python_module = info["python_module"] || ""
        String.starts_with?(python_module, library.python_name)
      end)
      |> Enum.map(&function_symbol/1)

    methods =
      manifest
      |> Map.get("classes", %{})
      |> Map.values()
      |> Enum.filter(fn info ->
        python_module = info["python_module"] || ""
        String.starts_with?(python_module, library.python_name)
      end)
      |> Enum.flat_map(&class_method_symbols/1)

    {functions, methods}
  end

  defp function_symbol(info) do
    %{
      name: symbol_name(info["module"], info["name"]),
      signature_source: info["signature_source"] || "runtime",
      signature_detail: info["signature_detail"],
      doc_source: info["doc_source"] || "runtime",
      signature_missing_reason: info["signature_missing_reason"],
      doc_missing_reason: info["doc_missing_reason"]
    }
  end

  defp class_method_symbols(class_info) do
    module = class_info["module"] || ""

    class_info
    |> Map.get("methods", [])
    |> Enum.map(fn method ->
      %{
        name: symbol_name(module, method_name(method)),
        signature_source: method["signature_source"] || "runtime",
        signature_detail: method["signature_detail"],
        doc_source: method["doc_source"] || "runtime",
        signature_missing_reason: method["signature_missing_reason"],
        doc_missing_reason: method["doc_missing_reason"]
      }
    end)
  end

  defp symbol_name(module, name) do
    base = if module in [nil, ""], do: "Unknown", else: module
    suffix = if name in [nil, ""], do: "unknown", else: name
    base <> "." <> suffix
  end

  defp method_name(%{"elixir_name" => name}) when is_binary(name), do: name
  defp method_name(%{elixir_name: name}) when is_binary(name), do: name
  defp method_name(%{"name" => name}) when is_binary(name), do: name
  defp method_name(%{name: name}) when is_binary(name), do: name
  defp method_name(_), do: "unknown"

  defp count_by(items, fun) do
    items
    |> Enum.map(fun)
    |> Enum.map(&SignatureTiers.normalize/1)
    |> Enum.frequencies()
    |> Enum.map(fn {key, value} -> {key || "unknown", value} end)
    |> Map.new()
  end

  defp non_variadic_ratio(symbols) do
    total = max(length(symbols), 1)
    non_variadic = Enum.count(symbols, fn symbol -> symbol.signature_source != "variadic" end)
    non_variadic / total
  end

  defp doc_coverage_ratio(symbols) do
    total = max(length(symbols), 1)
    with_docs = Enum.count(symbols, fn symbol -> symbol.doc_source != "empty" end)
    with_docs / total
  end

  defp stub_sources(symbols) do
    symbols
    |> Enum.filter(fn symbol -> symbol.signature_source in ["stub", "stubgen"] end)
    |> Enum.map(& &1.signature_detail)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp symbol_issues(symbol) do
    issues = []

    issues =
      if symbol.signature_source == "variadic" do
        issues ++
          [
            %{
              type: "signature_missing",
              symbol: symbol.name,
              source: symbol.signature_source,
              reason: symbol.signature_missing_reason || "no signature sources succeeded"
            }
          ]
      else
        issues
      end

    if symbol.doc_source == "empty" do
      issues ++
        [
          %{
            type: "doc_missing",
            symbol: symbol.name,
            source: symbol.doc_source,
            reason: symbol.doc_missing_reason || "docstring missing"
          }
        ]
    else
      issues
    end
  end

  defp library_errors(library, errors) do
    errors
    |> Enum.filter(fn error ->
      error.library == library.name or error.library == library.python_name
    end)
    |> Enum.map(fn error ->
      %{
        type: "introspection_error",
        library: error.library,
        python_module: error.python_module,
        reason: normalize_error_reason(error.reason)
      }
    end)
  end

  defp normalize_error_reason(%IntrospectionError{} = error) do
    %{
      "type" => Atom.to_string(error.type),
      "message" => error.message,
      "package" => error.package,
      "python_error" => error.python_error,
      "suggestion" => error.suggestion
    }
  end

  defp normalize_error_reason(%_{} = error) do
    Map.from_struct(error)
  end

  defp normalize_error_reason(reason), do: reason

  defp markdown_report(report) do
    summary = report["summary"] || %{}
    issues = report["issues"] || []

    lines = [
      "# Coverage Report: #{report["library"]}",
      "",
      "Generated at: #{report["generated_at"]}",
      "",
      "## Summary",
      "",
      "- Symbols: #{summary["symbols_total"]}",
      "- Functions: #{summary["functions"]}",
      "- Class methods: #{summary["class_methods"]}",
      "- Non-variadic ratio: #{format_ratio(summary["non_variadic_ratio"])}",
      "- Doc coverage ratio: #{format_ratio(summary["doc_coverage_ratio"])}",
      "",
      "## Stubs Used",
      "",
      format_stub_sources(report["stubs"] || %{}),
      "",
      "## Signature Tiers",
      "",
      format_counts(summary["signature_tiers"] || %{}),
      "",
      "## Doc Tiers",
      "",
      format_counts(summary["doc_tiers"] || %{}),
      "",
      "## Issues",
      ""
    ]

    issue_lines =
      if issues == [] do
        ["No issues detected."]
      else
        Enum.map(issues, &format_issue/1)
      end

    (lines ++ issue_lines)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp format_counts(counts) do
    counts
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.map_join("\n", fn {key, value} -> "- #{key}: #{value}" end)
  end

  defp format_issue(issue) do
    type = Map.get(issue, :type) || Map.get(issue, "type") || "unknown"
    symbol = Map.get(issue, :symbol) || Map.get(issue, "symbol")
    library = Map.get(issue, :library) || Map.get(issue, "library")
    base = "- [#{type}] #{symbol || library || "unknown"}"

    details =
      issue
      |> Map.drop([:type, "type", :symbol, "symbol", :library, "library"])
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

    if details == "" do
      base
    else
      base <> " (" <> details <> ")"
    end
  end

  defp format_stub_sources(%{"sources" => sources}) when is_list(sources) do
    if sources == [] do
      "No stubs used."
    else
      Enum.map_join(sources, "\n", fn source -> "- #{source}" end)
    end
  end

  defp format_stub_sources(_), do: "No stubs used."

  defp format_ratio(nil), do: "0.0"
  defp format_ratio(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_ratio(value), do: to_string(value)
end
