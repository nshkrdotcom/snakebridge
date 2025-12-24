# Prototype: `snakebridge.inspect` Diagnostic Tooling

## 1. Goals
- Provide a single command that profiles a generated module (or config) against real Python execution.
- Surface instrumentation data as actionable diagnostics (warnings, suggestions, automatic profile adjustments).
- Enable CI enforcement (fail builds when adapters behave outside declared profiles).

## 2. Command Overview
```
mix snakebridge.inspect <module_or_config>
  --session <id>          # reuse session for deterministic runs
  --sample <N>            # number of invocations per method (default: 1)
  --inputs path.json      # optional sample payloads
  --format human|json     # output mode
  --enforce               # exit non-zero on critical mismatches
```

### Example
```
mix snakebridge.inspect Demo.Predict --sample 3 --format human
```
Output snippet:
```
[Demo.Predict.call]
  Declared profile :function
  Observed         :stream (generator yields 5 chunks)
  Action           Suggest updating config: execution_mode: :stream
  Evidence         Telemetry span run_id=abc latency=1200ms chunk_count=5
```

## 3. Architecture
1. **Target Resolution**
   - Accept either compiled module (`Elixir.MyAdapter`) or config identifier.
   - Load associated `SnakeBridge.Config` and generated metadata.
2. **Probe Runner**
   - Spins up a dedicated Snakepit session (unless provided) and invokes each method/function using sample inputs.
   - Wraps calls with telemetry spans to capture timings, streaming behavior, async hints, errors.
3. **Telemetry Collector**
   - Subscribes to `[:snakepit, :request, ...]` and Python bridge events, correlating via `run_id`.
   - Normalizes events into `ExecutionReport` structs.
4. **Analyzer**
   - Compares `ExecutionReport` vs. declared profile.
   - Detects anomalies (e.g., streaming data on :function profile, long blocking tasks, missing heartbeats, callback usage without bidirectional tools enabled).
   - Rates severity: info/warning/error.
5. **Reporter**
   - Formats findings (CLI, JSON) with suggested config patches.
   - When `--enforce` is set, exits non-zero on severity ≥ warning.

## 4. Telemetry Schema
| Event | Key Metadata | Purpose |
| --- | --- | --- |
| `[:snakepit, :request, :executed]` | `run_id`, `duration_us`, `adapter`, `session_id` | Baseline latency + routing |
| `[:snakepit, :stream, :chunk]` | `run_id`, `chunk_index`, `payload_bytes` | Detect streaming/generator behavior |
| `[:snakepit, :worker, :async_hint]` (new) | `run_id`, `awaited?`, `generator?`, `callback?` | Python-side instrumentation feeds hints |
| `[:snakebridge, :profile, :diagnostic]` | `profile_id`, `run_id`, `severity`, `suggestion` | Aggregated analyzer output |

## 5. Developer Workflow
1. Author config or generate modules.
2. Run `mix snakebridge.inspect <target>` locally; fix warnings.
3. Commit config + generated docs.
4. CI runs the same command with `--enforce` to prevent regressions.

## 6. Future Enhancements
- **Auto-patching**: `--apply` flag writes suggested profile changes back to config.
- **Replay mode**: feed previously captured telemetry to reproduce issues without rerunning Python.
- **Dashboard export**: emit OpenTelemetry traces for richer visualization in Grafana/Tempo.
