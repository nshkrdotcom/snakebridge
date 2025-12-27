# Agent Prompt: SnakeBridge FFI Ergonomics

## Mission

Implement the FFI ergonomics plan in `design.md` for SnakeBridge. Focus on a
helper registry, helper discovery, generated helper wrappers, and clear error
handling. Keep behavior explicit and safe by default.

## Required Reading (Full Paths)

- /home/home/p/g/n/snakebridge/docs/20251226/ffi-ergonomics/design.md

Core source to inspect and modify:

- /home/home/p/g/n/snakebridge/lib/snakebridge/runtime.ex
- /home/home/p/g/n/snakebridge/lib/snakebridge/config.ex
- /home/home/p/g/n/snakebridge/lib/snakebridge/python_env.ex
- /home/home/p/g/n/snakebridge/lib/snakebridge/introspector.ex
- /home/home/p/g/n/snakebridge/lib/snakebridge/environment_error.ex
- /home/home/p/g/n/snakebridge/lib/snakebridge/introspection_error.ex
- /home/home/p/g/n/snakebridge/priv/python/snakebridge_adapter.py

Test patterns to follow:

- /home/home/p/g/n/snakebridge/test

## Implementation Rules

- Use TDD: write failing tests first, implement minimal code to pass, refactor.
- Do not add new behavior without test coverage.
- Helper registry must be explicit and opt-in; inline execution remains disabled
  by default.
- Maintain backwards compatibility with existing runtime contract.
- Keep logging and error messages actionable for users.

## Quality Gates

- All tests must pass.
- No warnings or runtime errors.
- Format checks must pass (`mix format --check-formatted`).

## Deliverables

- Helper registry and discovery (project helpers + optional helper pack).
- Generated helper wrappers for known helpers.
- Error classification for missing helpers or non-serializable args.
- Tests for helper loading, calling, and failure modes.
- Documentation updates where needed.
