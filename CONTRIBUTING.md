# Contributing to SnakeBridge

Thanks for taking the time to contribute! SnakeBridge is focused on providing a smooth bridge between Elixir and the Python ecosystem, and we aim to keep the project approachable for new contributors. This guide covers the basics for getting started.

## Getting Started

- Fork the repository and create a topic branch from `main`.
- Ensure you have Elixir ≥ 1.14 and Erlang/OTP ≥ 25 installed.
- Install dependencies:

```bash
mix deps.get
```

- Run the test suite to make sure everything passes locally:

```bash
mix test
```

## Development Workflow

1. **Describe the problem** – Open an issue (or comment on an existing one) before starting large changes. This helps prevent duplicated work.
2. **Create a feature branch** – Use a descriptive name such as `feature/add-config-validator` or `bugfix/fix-cache-miss`.
3. **Write tests** – Add unit, integration, or property-based tests that cover the change. We rely heavily on automated tests.
4. **Keep commits focused** – Squash trivial commits and keep meaningful commit messages. Prefer the imperative mood, e.g. `Add schema validator for optional fields`.
5. **Run quality checks** – Ensure everything stays green locally:

```bash
mix quality
mix coveralls
```

6. **Document changes** – Update `README.md`, module docs, or `CHANGELOG.md` when behaviour changes or new features are introduced.
7. **Open a Pull Request** – Fill in the PR template with context, screenshots (if relevant), and testing notes.

## Coding Guidelines

- Follow the style enforced by `mix format` and Credo (`mix credo --strict`).
- Prefer descriptive function names and avoid large modules by extracting context-specific code.
- Document public functions using Elixir docstrings and typespecs where reasonable.
- Keep runtime dependencies minimal; prefer optional dependencies for integrations.
- When touching code generation or macros, add explanatory comments to help future contributors.

## Commit & PR Checklist

- [ ] Tests pass (`mix test`)
- [ ] Quality checks pass (`mix quality`)
- [ ] Coverage looks good (`mix coveralls`)
- [ ] New functionality documented
- [ ] CHANGELOG updated (when user-facing behaviour changes)

## Questions?

If you have questions or need feedback, open a discussion or ping the maintainers in the relevant GitHub issue/PR. Thanks again for helping to make SnakeBridge better!
