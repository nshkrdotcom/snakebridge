# SnakeBridge <> Snakepit 0.9.0 Alignment: Critical Review Prompt

## Context

Snakepit 0.9.0 introduces a redesigned script lifecycle (exit_mode/stop_mode, new env vars,
IO-safe exit path, and script shutdown telemetry). SnakeBridge depends on Snakepit and
ships a large set of examples + docs that reference script execution. Your mission is to
deeply review SnakeBridge for any required changes and to design a robust, testable
alignment plan.

This prompt includes preliminary findings and file references to speed you up. Use them
as starting points and validate them yourself.

## Summary of Snakepit 0.9.0 changes to consider

- run_as_script/2 now resolves exit behavior via exit_mode (:none|:halt|:stop|:auto),
  with SNAKEPIT_SCRIPT_EXIT env var and a legacy :halt flag.
- stop_mode (:if_started|:always|:never) prevents stopping Snakepit when embedded.
- exit paths are IO-safe; no direct IO before System.halt/stop.
- new script shutdown telemetry events under [:snakepit, :script, :shutdown, ...].
- new shutdown orchestrator that orders stop -> cleanup -> exit.

## Preliminary findings in SnakeBridge (with file references)

1) Examples use Snakepit.run_as_script/2 without exit_mode/stop_mode options. Decide
   whether to update to exit_mode: :auto or keep defaults and document why.
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

2) Example READMEs mention run_as_script/2 but do not mention exit_mode/stop_mode or
   SNAKEPIT_SCRIPT_EXIT.
   - `../snakebridge/examples/math_demo/README.md:15`
   - `../snakebridge/examples/proof_pipeline/README.md:21`

3) SnakeBridge README declares a Snakepit requirement of ~> 0.8.9, which likely needs
   to be updated to 0.9.0 after alignment.
   - `../snakebridge/README.md:706-711`

4) SnakeBridge mix.exs still references Snakepit 0.8.9 in comments; dependency is
   currently a path dep. Decide whether to update the version and release guidance.
   - `../snakebridge/mix.exs:45-46`

5) Existing prompt docs still state Snakepit 0.8.0 as the dependency target.
   - `../snakebridge/docs/20251227/IMPLEMENTATION_PROMPT.md:7`

6) Telemetry integration is focused on Python call events; decide whether to forward or
   document the new Snakepit script shutdown events.
   - `../snakebridge/lib/snakebridge/runtime.ex:693-731`
   - `../snakebridge/lib/snakebridge/telemetry/runtime_forwarder.ex:34-38`

7) Real Python test setup stops Snakepit directly if the pool is missing. Confirm that
   this is still the right behavior with the new stop_mode semantics.
   - `../snakebridge/test/support/real_python_case.ex:58-66`

## Engineering inquiries to answer

1) API/usage alignment:
   - Should SnakeBridge provide a first-class SnakeBridge.run_as_script/2 wrapper with
     safe defaults (exit_mode: :auto, stop_mode: :if_started) to avoid mistakes in
     examples and user code?
   - Should examples explicitly pass exit_mode: :auto (and possibly stop_mode) to align
     with Snakepit 0.9.0 guidance for scripts?
   - Should docs mention exit_mode/stop_mode and SNAKEPIT_SCRIPT_EXIT?

2) Telemetry:
   - Do we need to forward or surface Snakepit script shutdown telemetry events in
     SnakeBridge (new events under [:snakepit, :script, :shutdown, ...])?
   - If yes, define a SnakeBridge namespace mapping and metadata contract, plus tests.

3) Documentation + dependency hygiene:
   - Update SnakeBridge docs and README for Snakepit 0.9.0 behavior and env vars.
   - Audit docs for 0.8.0/0.8.9 references and update to 0.9.0 where appropriate.

4) Tests and robustness:
   - Do we need integration tests that run example scripts under --no-halt and confirm
     exit status? If so, design a portable harness.
   - Any tests needed to validate that embedded usage does not stop Snakepit (or the VM)?

5) Cross-cutting: consider any tooling (mix tasks, setup scripts, config helpers) that
   should mention or support new exit/stop semantics.

## Deliverables required from you

Create a full set of technical implementation docs and prompts under:

`../snakebridge/docs/20260101/snakepit-0.9.0-alignment/`

### Required docs (place in docs/src/)

Create these (you can rename, but keep the intent):

1) docs/src/01-current-state.md
   - current SnakeBridge usage of Snakepit run_as_script and telemetry
   - what breaks or is unclear with 0.9.0

2) docs/src/02-gap-analysis.md
   - list all alignment gaps and risks with file references

3) docs/src/03-design.md
   - proposed API changes, default behaviors, and compatibility notes
   - decisions on exit_mode/stop_mode handling and telemetry forwarding

4) docs/src/04-test-strategy.md
   - unit + integration test plan (portable, no GNU-only dependencies)

5) docs/src/05-docs-changelog.md
   - which docs must change and how
   - changelog update plan (append to 0.8.0 entry)

6) docs/src/06-prompt-sequence.md
   - ordered prompts (N prompts; you choose N based on scope)

### Required prompts (place in prompts/)

Create N prompt files (prompt-01-*.md, prompt-02-*.md, etc). Each prompt must:

- include "Required reading" pointing to docs/src you created
- include all context needed for a coding agent to implement
- mandate TDD (tests first)
- require all tests passing, no warnings, no dialyzer errors, no credo --strict issues
- update README and append to the 0.8.0 changelog entry (create the 0.8.0 entry if missing)
- avoid edits in vendored examples/**/deps or examples/**/_build

### Non-negotiables

- Keep content ASCII unless the existing file already uses non-ASCII.
- Use rg for searches where possible.
- Ensure new docs and prompts are self-contained and can be executed sequentially.
- If any step is blocked by missing files, document the blockage and provide a fallback.

## Output expectation for your work

When you finish, report:

- The doc set you created (paths)
- The prompt sequence you created (paths + purpose)
- Any assumptions or open questions
