# SnakeBridge <> Snakepit 0.9.0 Alignment - Technical Implementation Plan

## Goal

Align SnakeBridge with Snakepit 0.9.0 script lifecycle and telemetry semantics,
and harden the integration so scripts and docs are safe by default.

## Scope

- Script lifecycle alignment (exit_mode/stop_mode usage and docs).
- Telemetry forwarding for new Snakepit script shutdown events.
- Tests that validate behavior under script and embedded usage.
- Documentation and changelog updates in SnakeBridge.

Non-goals:
- Changes to Snakepit core behavior.
- Changes to vendored files under examples/**/deps or examples/**/_build.
- Large refactors of runtime call flow outside the script wrapper.

## Current state (key references)

Script usage in examples (Snakepit.run_as_script/2 directly, no exit_mode/stop_mode):
- `../snakebridge/examples/basic/lib/demo.ex:11`
- `../snakebridge/examples/bridge_client_example/lib/demo.ex:15`
- `../snakebridge/examples/class_constructor_example/lib/demo.ex:9`
- `../snakebridge/examples/class_resolution_example/lib/demo.ex:9`
- `../snakebridge/examples/docs_showcase/lib/demo.ex:14`
- `../snakebridge/examples/dynamic_dispatch_example/lib/demo.ex:18`
- `../snakebridge/examples/error_showcase/lib/demo.ex:20`
- `../snakebridge/examples/math_demo/lib/demo.ex:9`
- `../snakebridge/examples/proof_pipeline/lib/demo.ex:9`
- `../snakebridge/examples/protocol_integration_example/lib/demo.ex:11`
- `../snakebridge/examples/python_idioms_example/lib/demo.ex:14`
- `../snakebridge/examples/session_lifecycle_example/lib/demo.ex:20`
- `../snakebridge/examples/signature_showcase/lib/demo.ex:9`
- `../snakebridge/examples/streaming_example/lib/demo.ex:9`
- `../snakebridge/examples/strict_mode_example/lib/demo.ex:9`
- `../snakebridge/examples/telemetry_showcase/lib/demo.ex:21`
- `../snakebridge/examples/twenty_libraries/lib/demo.ex:14`
- `../snakebridge/examples/types_showcase/lib/demo.ex:18`
- `../snakebridge/examples/universal_ffi_example/lib/demo.ex:30`
- `../snakebridge/examples/wrapper_args_example/lib/demo.ex:9`

Example README mentions run_as_script/2 with no exit_mode/stop_mode guidance:
- `../snakebridge/examples/math_demo/README.md:15`
- `../snakebridge/examples/proof_pipeline/README.md:21`

SnakeBridge README pins Snakepit ~> 0.8.9:
- `../snakebridge/README.md:706-711`

Snakepit dependency comment in mix.exs references 0.8.9:
- `../snakebridge/mix.exs:45-46`

SnakeBridge docs still declare Snakepit 0.8.0 dependency target:
- `../snakebridge/docs/20251227/IMPLEMENTATION_PROMPT.md:7`

Telemetry forwarding today only covers Snakepit call events:
- `../snakebridge/lib/snakebridge/telemetry/runtime_forwarder.ex:34`
- `../snakebridge/lib/snakebridge/runtime.ex:693`

Real Python test support stops Snakepit if pool missing:
- `../snakebridge/test/support/real_python_case.ex:58-66`

## Design decisions

1) Add a SnakeBridge.run_as_script/2 wrapper with safe defaults.
   - Default exit behavior: exit_mode: :auto
   - Default stop behavior: stop_mode: :if_started
   - If user passes :exit_mode or :halt, do not override.
   - If user passes :stop_mode, do not override.
   - Let Snakepit resolve env vars and precedence; wrapper only sets defaults.

2) Update examples to call SnakeBridge.run_as_script/2 (not Snakepit.run_as_script/2).
   - Reduces copy/paste errors.
   - Centralizes behavior.

3) Add telemetry forwarder for Snakepit script shutdown events.
   - Forward: [:snakepit, :script, :shutdown, :start|:stop|:cleanup|:exit]
     to [:snakebridge, :script, :shutdown, ...]
   - Preserve metadata, add snakebridge_version.
   - Do not auto-attach; expose attach/0 and detach/0 like the existing runtime
     forwarder.

4) Update docs to describe exit_mode/stop_mode and SNAKEPIT_SCRIPT_EXIT.
   - README scripts and requirements section.
   - Example READMEs.
   - Implementation prompt docs that reference Snakepit 0.8.x.

5) Tests must validate both script and embedded use.
   - Unit tests for wrapper option merging.
   - Telemetry forwarder tests (event mapping + metadata).
   - Integration tests using a portable subprocess harness (no GNU-only tools).

## Implementation plan

### Phase 1: Wrapper API and examples

- Add SnakeBridge.run_as_script/2 in `../snakebridge/lib/snakebridge.ex`.
  - Signature: run_as_script(fun, opts \\ []) when is_function(fun, 0)
  - Apply defaults: exit_mode: :auto, stop_mode: :if_started
  - Do not override :exit_mode, :halt, or :stop_mode if set.
  - Delegate to Snakepit.run_as_script/2 with merged opts.

- Update all examples to call SnakeBridge.run_as_script/2.
  - Replace Snakepit.run_as_script in examples listed above.

- Update example READMEs to mention:
  - exit_mode defaults
  - stop_mode defaults
  - SNAKEPIT_SCRIPT_EXIT env var for scripts

Acceptance:
- All example modules compile and run with unchanged behavior.
- New wrapper has tests.

### Phase 2: Script shutdown telemetry forwarding

- Create `SnakeBridge.Telemetry.ScriptShutdownForwarder` in
  `../snakebridge/lib/snakebridge/telemetry/script_shutdown_forwarder.ex`.
  - attach/0 and detach/0
  - events: [:snakepit, :script, :shutdown, :start|:stop|:cleanup|:exit]
  - re-emit under [:snakebridge, :script, :shutdown, ...]
  - add :snakebridge_version metadata

- Add tests:
  - attach/detach behavior
  - event mapping and metadata preservation
  - no crash if telemetry app not started (match existing patterns)

Acceptance:
- Telemetry forwarder behaves like RuntimeForwarder in style and API.

### Phase 3: Test harness for exit/stop semantics

- Create a portable subprocess harness:
  - Use System.cmd/3 with Task.yield + Task.shutdown for timeouts.
  - Avoid GNU-only tools like timeout --foreground.

- Add integration tests:
  - Wrapper with exit_mode :auto under --no-halt returns with expected status.
  - Wrapper in embedded mode does not stop Snakepit when already started.
  - SNAKEPIT_SCRIPT_EXIT env var flows through wrapper.

- Confirm RealPythonCase behavior:
  - Review the use of Application.stop/1 to ensure it still makes sense with
    stop_mode defaults.
  - Keep explicit stop behavior if test isolation requires it.

Acceptance:
- Integration tests pass on Linux and macOS.

### Phase 4: Docs + changelog alignment

- README:
  - Update Snakepit requirement from ~> 0.8.9 to ~> 0.9.0.
  - Document SnakeBridge.run_as_script/2 wrapper and default exit_mode/stop_mode.
  - Document SNAKEPIT_SCRIPT_EXIT and legacy SNAKEPIT_SCRIPT_HALT behavior.

- Update docs/20251227/IMPLEMENTATION_PROMPT.md dependency references.

- Update example READMEs (math_demo, proof_pipeline) with new script guidance.

- CHANGELOG:
  - Ensure a 0.8.0 entry exists and append alignment notes to that entry as
    required by project policy.

Acceptance:
- Docs consistent with Snakepit 0.9.0 semantics.

## Test plan (summary)

Unit tests:
- Wrapper option merging (exit_mode/stop_mode defaults).
- Telemetry forwarder event mapping.

Integration tests:
- Subprocess execution with exit_mode :auto + --no-halt.
- Embedded usage (Snakepit already started) does not stop the VM.
- Env var SNAKEPIT_SCRIPT_EXIT honored when wrapper opts unset.

Quality gates:
- mix test
- credo --strict
- dialyzer
- no warnings or errors

## Risks and mitigations

- Risk: wrapper overrides user intent.
  - Mitigation: only set defaults when options are absent.

- Risk: telemetry forwarder conflicts with existing handlers.
  - Mitigation: use a unique handler ID and allow attach/detach.

- Risk: subprocess tests flaky due to Python/venv.
  - Mitigation: tag or skip if Python deps unavailable; use clear diagnostics.

## Open questions

- Should SnakeBridge expose its own env var (e.g., SNAKEBRIDGE_SCRIPT_EXIT) or
  rely solely on Snakepit’s SNAKEPIT_SCRIPT_EXIT?
- Should script shutdown telemetry be included in existing metrics/log handlers
  by default or remain opt-in?

## Deliverable checklist

- Wrapper API implemented + tested.
- Examples updated to use wrapper.
- Script shutdown telemetry forwarder implemented + tested.
- Integration tests for exit/stop semantics.
- README + example READMEs updated.
- Changelog updated with 0.8.0 alignment notes.
